/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

// Check mandatory parameters


/*
========================================================================================
    IMPORT LOCAL MODULES/SUBWORKFLOWS
========================================================================================
*/

// Don't overwrite global params.modules, create a copy instead and use that within the main script.
def modules = params.modules.clone()

include { SRA_IDS_TO_RUNINFO      } from '../../modules/local/sra_ids_to_runinfo'      addParams( options: modules['sra_ids_to_runinfo']      )
include { SRA_RUNINFO_TO_FTP      } from '../../modules/local/sra_runinfo_to_ftp'      addParams( options: modules['sra_runinfo_to_ftp']      )
include { SRA_FASTQ_FTP           } from '../../modules/local/sra_fastq_ftp'           addParams( options: modules['sra_fastq_ftp']           )
include { SRA_TO_SAMPLESHEET      } from '../../modules/local/sra_to_samplesheet'      addParams( options: modules['sra_to_samplesheet'], results_dir: modules['sra_fastq_ftp'].publish_dir )
include { SRA_MERGE_SAMPLESHEET   } from '../../modules/local/sra_merge_samplesheet'   addParams( options: modules['sra_merge_samplesheet']   )
include { MULTIQC_MAPPINGS_CONFIG } from '../../modules/local/multiqc_mappings_config' addParams( options: modules['multiqc_mappings_config'] )
include { GET_SOFTWARE_VERSIONS   } from '../../modules/local/get_software_versions'   addParams( options: [publish_files : ['tsv':'']]       )

/*
========================================================================================
    RUN MAIN WORKFLOW
========================================================================================
*/

workflow FETCHNGS {
    take:
    ch_pathToIDs //path to id list

    main:
    
    println "=== FETCHNGS ==="
    
    ch_software_versions = Channel.empty()
    
    ch_pathToIDs
            .splitCsv(header:false, sep:'', strip:true)
            .map { it[0] }
            .unique()
            .set { ch_ids }

    //
    // MODULE: Get SRA run information for public database ids
    //
    SRA_IDS_TO_RUNINFO (
        ch_ids,
        params.ena_metadata_fields ?: ''
    )

    //
    // MODULE: Parse SRA run information, create file containing FTP links and read into workflow as [ meta, [reads] ]
    //
    SRA_RUNINFO_TO_FTP (
        SRA_IDS_TO_RUNINFO.out.tsv
    )
    /*
    SRA_RUNINFO_TO_FTP
        .out
        .tsv
        .splitCsv(header:true, sep:'\t')
        .map {
            meta ->
                meta.single_end = meta.single_end.toBoolean()
                [ meta, [ meta.fastq_1, meta.fastq_2 ] ]
        }
        .unique()
        .set { ch_sra_reads }
    */
    ch_software_versions = ch_software_versions.mix(SRA_RUNINFO_TO_FTP.out.version.first().ifEmpty(null))

    if (!params.skip_fastq_download) {
        //
        // MODULE: If FTP link is provided in run information then download FastQ directly via FTP and validate with md5sums
        //
        SRA_FASTQ_FTP (
            SRA_RUNINFO_TO_FTP.out.tsv
        )
        /*
        //
        // MODULE: Stage FastQ files downloaded by SRA together and auto-create a samplesheet
        //
        SRA_TO_SAMPLESHEET (
            SRA_FASTQ_FTP.out.fastq,
            params.nf_core_pipeline ?: '',
            params.sample_mapping_fields
        )

        //
        // MODULE: Create a merged samplesheet across all samples for the pipeline
        //
        SRA_MERGE_SAMPLESHEET (
            SRA_TO_SAMPLESHEET.out.samplesheet.collect{it[1]},
            SRA_TO_SAMPLESHEET.out.mappings.collect{it[1]}
        )

        //
        // MODULE: Create a MutiQC config file with sample name mappings
        //
        if (params.sample_mapping_fields) {
            MULTIQC_MAPPINGS_CONFIG (
                SRA_MERGE_SAMPLESHEET.out.mappings
            )
        }

        //
        // If ids don't have a direct FTP download link write them to file for download outside of the pipeline
        //
        def no_ids_file = ["${params.outdir}", "${modules['sra_fastq_ftp'].publish_dir}", "IDS_NOT_DOWNLOADED.txt" ].join(File.separator)
        ch_sra_reads
            .map { meta, reads -> if (!meta.fastq_1) "${meta.id.split('_')[0..-2].join('_')}" }
            .unique()
            .collectFile(name: no_ids_file, sort: true, newLine: true)
      */
    }

    //
    // MODULE: Pipeline reporting
    //
    ch_software_versions
        .map { it -> if (it) [ it.baseName, it ] }
        .groupTuple()
        .map { it[1][0] }
        .flatten()
        .collect()
        .set { ch_software_versions }

    GET_SOFTWARE_VERSIONS (
        ch_software_versions.map { it }.collect()
    )
    
    emit:
    samplesheet = SRA_FASTQ_FTP.out.samplesheet
}

/*
========================================================================================
    COMPLETION EMAIL AND SUMMARY
========================================================================================
*/
/*
workflow.onComplete {
    NfcoreTemplate.email(workflow, params, summary_params, projectDir, log)
    NfcoreTemplate.summary(workflow, params, log)
    WorkflowFetchngs.curateSamplesheetWarn(log)
}
*/
/*
========================================================================================
    THE END
========================================================================================
*/
