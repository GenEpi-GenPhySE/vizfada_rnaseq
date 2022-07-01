# VizFaDa RNA-seq pipeline

A **Nextflow** pipeline to download [FAANG](https://data.faang.org/) RNA-seq data,
launch Salmon pseudo-alignment and fastQC in batch, and clean behind
it by removing heavy `fastq` & `bam` files, and the Nextflow `work` directory.

Used to process all FAANG RNA-seq files for the [VizFaDa](https://viz.faang.org/) project.

## Usage
At the moment, the pipeline should run (at least) on the [Genotoul](http://bioinfo.genotoul.fr/) and [Embassy Cloud](http://www.embassycloud.org/).


## Pipeline tuning

### Reference genomes
Reads will be align to Ensembl reference genomes (automatically retrieved at the begining of the pipeline) as specified by 
[this configuration file](https://github.com/GenEpi-GenPhySE/vizfada_rnaseq/blob/master/conf/species.config).
