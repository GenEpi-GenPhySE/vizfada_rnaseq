/*
 * Copyright (c) 2013-2019, Centre for Genomic Regulation (CRG).
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 *
 */


/*
 * RNASeq pipeline for VizFaDa
 *
 * Authors:
 * - Laura Morel <laura.morel@inrae.fr>
 * - Paolo Di Tommaso <paolo.ditommaso@gmail.com>
 * - Emilio Palumbo <emiliopalumbo@gmail.com>
 * - Evan Floden <evanfloden@gmail.com>
 */


/*
 * Default pipeline parameters. They can be overriden on the command line eg.
 * given `params.foo` specify on the run command line `--foo some_value`.
 */

params.species_ensembl = "$baseDir/data/species_ensembl.txt"
params.outdir = "results"
params.multiqc = "$baseDir/multiqc"
params.fastqc = false
params.salmon = ""
params.species = "Gallus gallus"
params.input = "$baseDir/data/test_input.txt"
params.cpus = 3
params.data = "/data"
params.all = false

species=params.species.replaceAll(/ /, "_")
index=file("${params.data}/${species}/index", type:"dir")

log.info """\
 R N A S E Q - N F   P I P E L I N E
 ===================================
 species      : ${params.species}
 baseDir      : ${baseDir}
 index        : ${index}
 outdir       : ${params.outdir}
 cpus         : ${params.cpus}
 fastqc       : ${params.fastqc}
 input        : ${params.input}
 """

if (params.all) {
    process getMetaAndInput {
        tag "$species"
        container 'lauramble/r-vizfada'
        publishDir "$outDir", pattern: 'metadata.tsv' 
        
        input:
        val species from Channel.from(params.species)
        
        output:
        stdout into ch_input
        file 'metadata.tsv'
        
        shell:
        """
        bash $baseDir/scripts/extraction_faang.sh '$species' &> temp.txt
        Rscript $baseDir/sctipts/GetMeta.R specimens.json experiments.json species.json
        cat input.txt
        """      
    }
} else {
    ch_input=Channel.fromList(input.readLines())
}

if (!index.exists()) {
    process getcDNA {
        tag "$species"
        
        input:
        val species
        
        output:
        file "*.fa.gz" into ch_transcriptome
        
        shell:
        """
        version=\$( grep $species $params.species_ensembl | awk '{print \$2}' )
        url=\$( awk 'NR==1{print \$2}' $params.species_ensembl | sed "s/SPECIES/\\L$species/1; s/SPECIES.VERSION/$species.\$version/1" )
        wget \$url
        """
    }
    
    process index {
        tag "$transcriptome.simpleName"
        publishDir "$params.data/$species", mode:'copy'
        publishDir params.outdir
        cpus params.cpus

        input:
        path transcriptome from ch_transcriptome

        output:
        path "index"

        script:
        """
        # code some changes in your script and save them
        salmon index --threads $task.cpus -t $transcriptome -i index
        """
    }
}

 

if (params.fire){
    baseURL='https://hh.fire.sdo.ebi.ac.uk/fire/public/era'
    regex='"/fastq/.*\\.fastq\\.gz"'
} else {
    baseURL=''
    regex='"ftp.*\\.fastq\\.gz"'
}

process dlFromFaangAndQuant {
    tag "$accession"
    maxForks 10
    if (params.keepReads) {publishDir "${params.outDir}/reads", pattern: "*.fastq.gz", mode: 'copy'}
    publishDir "${params.outdir}/quant", mode:'copy', pattern: "${accession}"
    errorStrategy 'retry'
    maxErrors 5    
    cpus params.cpus
    
    input:
    each accession from ch_input
    file index

    output:
    path "${accession}" into quant_ch, quant2_ch
    
    shell:
    '''
    checkpaired=$(wget "http://data.faang.org/api/file/_search/?size=25000" --post-data '{"query": { "wildcard": {"name": "'!{accession}'*"}}}' -q -O - | grep -Po "!{accession}(_[12])+")
    
    if (( $(echo $checkpaired | wc -w) != 0 ))
    then
        files="!{accession}_1 !{accession}_2"
    else
        files=!{accession}
    fi
    
    md5=""
    for file in $files
    do 
      url=$(wget "http://data.faang.org/api/file/$file" -q -O - | grep -Po !{regex})
      url=!{baseURL}$url
      checksum=$(wget http://data.faang.org/api/file/$file -q -O - | grep '"checksum": ".*?",' -Po | cut -d'"' -f4)
      while [[ $md5 != $checksum ]]
      do
        wget $url -q -O $file".fastq.gz"
        md5=$(md5sum $file".fastq.gz" | cut -d" " -f1)
      done
    done
    
    if (( $(echo $files | wc -w) == 2))
    then
        reads_1=!{accession}_1.fastq.gz
        reads_2=!{accession}_2.fastq.gz
        salmon quant --threads !{task.cpus} -l A -i !{index} -1 $reads_1 -2 $reads_2 -o !{accession} !{params.salmon}
    else
        salmon quant --threads !{task.cpus} -l A -i !{index} -r !{accession}.fastq.gz -o !{accession} !{params.salmon}
    fi
    
    rm -rf *.fastq.gz
    
    echo $PWD
    '''
}


/*
if ( params.index != "" ) {
    index_ch = Channel.fromPath( params.index )
} else {
    process index {
        tag "$transcriptome.simpleName"
        publishDir params.outdir, mode:'copy'
        cpus params.cpus

        input:
        path transcriptome from params.transcriptome

        output:
        path 'index' into index_ch

        script:
        """
        # code some changes in your script and save them
        salmon index --threads $task.cpus -t $transcriptome -i index
        """
    }
}


process quant_pair {
    tag "$pair_id"
    publishDir "${params.outdir}/quant", mode:'copy'
    cpus params.cpus
    errorStrategy 'retry'
    maxErrors 5
    
    when:
    index.exists()

    input:
    file index from index
    tuple val(pair_id), path(reads_1), path(reads_2) from read_pairs_ch

    output:
    path(pair_id) into (quant_pair_ch, quant_pair2_ch)

    script:
    """
    salmon quant --threads $task.cpus -l A -i $index -1 $reads_1 -2 $reads_2 -o $pair_id $params.salmon
    rm -rf "\$(readlink -f "$reads_1")" 
    rm -rf "\$(readlink -f "$reads_2")"
    """
}

process quant_single {
    tag "$id"
    publishDir "${params.outdir}/quant", mode:'copy'
    cpus params.cpus
    errorStrategy 'retry'
    maxErrors 5
    
    when:
    index.exists()

    input:
    file index from index
    tuple val(id), path(reads) from read_single_ch

    output:
    path(id) into (quant_single_ch, quant_single2_ch)

    script:
    """
    salmon quant --threads $task.cpus -l A -i $index -r $reads -o $id $params.salmon
    rm -rf "\$(readlink -f "$reads")"
    """
}
*/

if ( params.fastqc ) {

    process fastqc {
        tag "$sample_id"
        publishDir "${params.outdir}/FastQC", mode:'copy'

        input:
        tuple val(sample_id), path(reads) from reads_for_fastqc_ch
        output:
        path "fastqc_${sample_id}_logs" into fastqc_ch

        script:
        """
        mkdir fastqc_${sample_id}_logs
        fastqc -o fastqc_${sample_id}_logs -f fastq -q ${reads}
        """
    }

} else {
    fastqc_ch = Channel.empty()
}

process multiqc {
    publishDir params.outdir, mode:'copy'
    
    input:
    path 'data*/*' from quant_ch.mix(fastqc_ch).collect()
    path config from params.multiqc

    output:
    path 'multiqc_report.html'

    script:
    """
    cp $config/* .
    echo "custom_logo: \$PWD/logo.png" >> multiqc_config.yaml
    multiqc -v .
    """
}

process tximport {
    container 'lauramble/r-vizfada'
    publishDir params.outdir, mode:'copy'
    
    input:
    path "dummy" from quant2_ch.collect()
    path "quant" from Channel.fromPath("$params.outdir/quant")
    
    output:
    file "abundance.csv"
    
    script:
    """
    version=\$( grep $species $params.species_ensembl | awk '{print \$2}' )
    Rscript $baseDir/scripts/TPMpergene.R $quant "${params.species}" \$version
    """
}

workflow.onComplete {
	log.info ( workflow.success ? "\nDone! Open the following report in your browser --> $params.outdir/multiqc_report.html\n" : "Oops .. something went wrong" )
}

