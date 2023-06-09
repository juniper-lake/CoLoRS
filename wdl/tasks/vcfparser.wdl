version 1.0

import "../structs.wdl"

task postprocess_joint_vcf {
  input {
    File vcf
    String cohort_id
    Boolean anonymize_output
    Array[String]? sample_plus_sexes
    File? non_diploid_regions
    
    RuntimeAttributes runtime_attributes
  }

  String vcf_basename = basename(basename(vcf, ".gz"), ".vcf")
  String anonymize_prefix = if (anonymize_output) then "--anonymize_prefix ~{cohort_id}" else ""
  String outfile = if (anonymize_output) then "~{vcf_basename}.anonymized.vcf" else "~{vcf_basename}.vcf"
  String just_zip_index = if (anonymize_output) || defined(non_diploid_regions) || defined(sample_plus_sexes) then "false" else "true"
  
  Int threads = 4
  Int disk_size = ceil((size(vcf, "GB")) * 3.5 + 20) 


  command {
    set -euo pipefail

    # if you don't need to anonymize output or fix ploidy, then just zip and index
    if [[ ~{just_zip_index} == "true" ]]; then
      # if already zipped, just index
      if [[ $file =~ \.gz$ ]]; then
        mv ~{vcf} ~{outfile}.gz
      else
        bgzip -c \
          --threads ~{threads} \
          ~{vcf} \
          > ~{outfile}.gz
      fi
    else
      postprocess_joint_vcf.py \
        ~{anonymize_prefix} \
        --non_diploid_regions ~{non_diploid_regions} \
        --sample_sexes ~{sep=" " sample_plus_sexes} \
        --outfile ~{outfile} \
        ~{vcf}

      bgzip -c \
        --threads ~{threads} \
        ~{outfile}
    fi

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

    merge_trgt_vcfs.py \
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
    File merged_vcf = "~{outfile}.gz"
    File merged_vcf_index = "~{outfile}.gz.tbi"
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
