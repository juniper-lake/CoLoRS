version 1.0

import "../../tasks/glnexus.wdl" as GLnexus
import "../../tasks/pbsv.wdl" as Pbsv
import "../../tasks/sniffles.wdl" as Sniffles
import "../../tasks/hiphase.wdl" as Hiphase
import "../../tasks/utils.wdl" as Utils

workflow cohort_combine_samples {
  input {
    String cohort_id

    Array[String] sample_ids
    Array[IndexData] aligned_bams
    Array[Array[File]] svsigs
    Array[IndexData] gvcfs
    Array[File] snfs
    Array[IndexData] trgt_vcfs

    ReferenceData reference

    RuntimeAttributes default_runtime_attributes 
  }

  scatter (gvcf_object in gvcfs) {
		File gvcf = gvcf_object.data
		File gvcf_index = gvcf_object.index
	}

  # joint call small variants with GLnexus
  call Glnexus.glnexus {
    input:
      cohort_id = cohort_id,
      gvcfs = gvcf,
      gvcf_indexes = gvcf_index,
      reference_name = reference.name,
      runtime_attributes = default_runtime_attributes
  }

  # joint call structural variants with pbsv
  scatter (idx in range(length(reference.chromosomes))) {
    call Pbsv.pbsv_call {
      input:
        sample_id = cohort_id,
        svsigs = svsigs[idx],
        sample_count = length(sample_ids),
        region = reference.chromosomes[idx],
        reference_name = reference.name,
        reference_fasta = reference.fasta.data,
        reference_index = reference.fasta.index,
        runtime_attributes = default_runtime_attributes
    }
  }

  call Utils.concat_vcfs {
    input:
      vcfs = pbsv_call.vcf,
      output_vcf_name = "~{cohort_id}.~{reference.name}.pbsv.vcf",
      runtime_attributes = default_runtime_attributes
  }

  # joint call structural variants with sniffles
  call Sniffles.sniffles_call {
    input:
      sample_id = cohort_id,
      snfs = snfs,
      reference_name = reference.name,
      reference_fasta = reference.fasta.data,
      reference_index = reference.fasta.index,
      tr_bed = reference.tandem_repeat_bed,
      runtime_attributes = default_runtime_attributes
  }

  scatter (bam_object in aligned_bams) {
		File aligned_bam = bam_object.data
		File aligned_bam_index = bam_object.index
	}

  if (!aggregate) {
    # phase pbsv and deepvariant vcfs
    call Hiphase.hiphase {
      input:
        cohort_id = cohort_id,
        sample_ids = sample_ids,
        aligned_bams = aligned_bam,
        aligned_bam_indexes = aligned_bam_index,
        deepvariant_vcf = glnexus.vcf,
        deepvariant_vcf_index = glnexus.vcf_index,
        pbsv_vcf = concat_vcfs.concatenated_vcf,
        reference_fasta = reference.fasta.data,
        reference_index = reference.fasta.index,
        runtime_attributes = default_runtime_attributes
    }

    # zip and index pbsv structural variants
    call Utils.index_vcf as index_phased_pbsv_vcf {
      input:
        gzipped_vcf = hiphase.pbsv_output_vcf,
        runtime_attributes = default_runtime_attributes
    }

    call Utils.index_vcf as index_phased_deepvariant_vcf {
      input:
        gzipped_vcf = hiphase.deepvariant_output_vcf,
        runtime_attributes = default_runtime_attributes
    }

    call Utils.zip_index_vcf as zip_index_sniffles_vcf {
      input:
        vcf = sniffles_call.vcf,
        runtime_attributes = default_runtime_attributes
    }

   # combine trgt output in some way
  }

  # if (aggregate) {
  #   # randomize sniffles, pbsv, trgt, deepvariant
  # }

  output {
    IndexData cohort_deepvariant_vcf = { "data": select_first([index_phased_deepvariant_vcf.zipped_vcf]), "index": select_first([index_phased_deepvariant_vcf.zipped_vcf_index]) }
    IndexData cohort_pbsv_vcf = { "data": select_first([index_phased_pbsv_vcf.zipped_vcf]), "index": select_first([index_phased_pbsv_vcf.zipped_vcf_index]) }
    IndexData cohort_sniffles_vcf = { "data": select_first([zip_index_sniffles_vcf.zipped_vcf]), "index": select_first([zip_index_sniffles_vcf.zipped_vcf_index]) }
    # trgt, combine in some way?
    Array[File] cohort_pbsv_log = pbsv_call.log # for testing memory usage

    # Aggregate = false
    File? hiphase_stats = hiphase.stats
    File? hiphase_blocks = hiphase.blocks
    File? hiphase_summary = hiphase.summary
  }
    
}
