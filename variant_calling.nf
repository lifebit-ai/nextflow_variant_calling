#!/usr/bin/env nextflow

params.reads = 'data/SRR957824.fastq'
params.ref = 'data/pO157_Sakai.fasta'
params.adapt = 'data/adapters.fasta'
params.mode = 'illumina'
params.skip_plot_vcf = false

sequences = file(params.reads)
reference = file(params.ref)
adapters = file(params.adapt)

process adapter_trimming {
    input:
    file input from sequences
    file 'adapters.fasta' from adapters

    output:
    file "${input.baseName}.adapt" into adapt_trimmed

    script:
	if( params.mode == 'illumina' )
		"""
		scythe -q sanger -a adapters.fasta -o "${input.baseName}.adapt" $input
		"""
	else if( params.mode == 'ion' )
        """
        cp $input "${input.baseName}.adapt"
        """
    else
        error "Invalid alignment mode: ${params.mode}"

}

process quality_trimming {
    input:
    file input from adapt_trimmed

    output:
    file "${input.baseName}.trimmed" into trimmed

    """
    sickle se -f $input -t sanger -o "${input.baseName}.trimmed" -q 20
    """
}

process bowtie {
    input:
    file input from trimmed
    file ref_genome from reference

    output:
    file "${input.baseName}.sorted.bam" into mapped

    """
    bowtie2-build $ref_genome index
    bowtie2 -p 12 -x index -U $input -S "${input.baseName}.bam"
    samtools sort -@ 12 -o "${input.baseName}.sorted.bam" "${input.baseName}.bam"
    """
}

process mpileup {
    publishDir 'results'

    input:
    file input from mapped
    file ref_genome from reference

    output:
    file "${input.baseName}.vcf" into snp_file

    """
    samtools mpileup $input -o "${input.baseName}.vcf" -v -u
    """
}

/*
 * Generate plot from output vcf file
 */
process vcf_plot {
    tag "$vcf"
    publishDir 'results'
    container 'lifebitai/vcfr:latest'

    when:
    !params.skip_plot_vcf

 		input:
    file vcf from snp_file

 		output:
    file 'Rplots.pdf' into plot

 		script:
    """
    #!/usr/bin/env Rscript
 		library(vcfR)
    vcf_file <- "${vcf}"
    vcf <- read.vcfR(vcf_file, verbose = FALSE)
    plot(vcf)
    dev.off()
    """
}
