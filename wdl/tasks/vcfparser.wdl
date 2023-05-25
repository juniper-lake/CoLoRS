version 1.0

import "../structs.wdl"

task postprocess_joint_vcf {
  input {
    File vcf
    String cohort_id
    Boolean anonymize_output
    Array[String] sexes
    
    RuntimeAttributes runtime_attributes
  }

  String vcf_basename = basename(basename(vcf, ".gz"), ".vcf")
  String anonymize_prefix = if (anonymize_output) then "--anonymize_prefix ~{cohort_id}" else ""
  String outfile = if (anonymize_output) then "~{vcf_basename}.anonymized.vcf" else "~{vcf_basename}.vcf"
  
  Int threads = 4
	Int disk_size = ceil((size(vcf, "GB")) * 3.5 + 20) 


  command {
    set -euo pipefail

    fix_hemizygous_ploidy.py \
      --anonymize_prefix ~{anonymize_prefix} \
      --sexes ~{sep=" " sexes} \
      --outfile ~{outfile}
    
    bgzip \
			--threads ~{threads} \
			~{outfile} -c \
			> ~{outfile}.gz

    tabix \
			--preset vcf \
			~{outfile}.gz   
  }

  output {
    File postprocessed_vcf = "~{outfile}.gz"
    File postprocessed_vcf_index = "~{outfile}.gz.tbi"
  }

	runtime {
		cpu: threads
		memory: "4 GB"
		disk: "~{disk_size} GB"
    disks: "local-disk ~{disk_size} HDD"
		preemptible: runtime_attributes.preemptible_tries
		maxRetries: runtime_attributes.max_retries
		awsBatchRetryAttempts: runtime_attributes.max_retries
		queueArn: runtime_attributes.queue_arn
		zones: runtime_attributes.zones
		docker: "~{runtime_attributes.container_registry}/vcfparser:0.1.0"
	}

}

task merge_trgt_vcfs {
  input {
    Array[File] trgt_vcfs
    String cohort_id
    String reference_name
    Boolean anonymize_output

    RuntimeAttributes runtime_attributes
  }

  String anonymize_prefix = if (anonymize_output) then "--anonymize_prefix " + cohort_id else ""
  String outfile = if (anonymize_output) then "~{cohort_id}.~{reference_name}.trgt.anonymized.vcf" else "~{cohort_id}.~{reference_name}.trgt.vcf"
  Int threads = 4
	Int disk_size = ceil((size(trgt_vcfs, "GB")) * 3.5 + 20)

  command {
    set -euo pipefail

    aggregate_trgt_vcfs.py \
      --vcfs ~{sep=" " trgt_vcfs} \
      --outfile ~{outfile} \
      ~{anonymize_prefix}

    bgzip \
			--threads ~{threads} \
			~{outfile} -c \
			> ~{outfile}.gz

    tabix \
			--preset vcf \
			~{outfile}.gz   
    
  }

	output {
		File merged_trgt_vcf = "~{outfile}.gz"
		File merge_trgt_vcf_index = "~{outfile}.gz.tbi"
	}

	runtime {
		cpu: threads
		memory: "4 GB"
		disk: "~{disk_size} GB"
    disks: "local-disk ~{disk_size} HDD"
		preemptible: runtime_attributes.preemptible_tries
		maxRetries: runtime_attributes.max_retries
		awsBatchRetryAttempts: runtime_attributes.max_retries
		queueArn: runtime_attributes.queue_arn
		zones: runtime_attributes.zones
		docker: "~{runtime_attributes.container_registry}/vcfparser:0.1.0"
	}
}