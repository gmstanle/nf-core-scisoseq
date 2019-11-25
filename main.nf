#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/scisoseq
========================================================================================
 nf-core/scisoseq Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/scisoseq
----------------------------------------------------------------------------------------
*/

/*
* Input is a single .bam file of CCS reads (name.ccs.bam) plus index file.
* If there is output from multiple flowcells, merge them with bamtools merge 
* (NOT samtools,see https://github.com/PacificBiosciences/PacBioFileFormats/wiki/BAM-recipes#merging).
* Then index with pbindex.
* Future versions of the pipeline should include these steps for reproducibility.
*/

/*
* Most of the processes in the pipeline are designed to save their output, even though mostly their
* output is intermediate and not used for downstream analysis. That is why they have 
* publishDir calls and why everything is saved as a file with a specific name, rather than
* just passed to a channel and therefore only saved to tmp working folders (which would be the most Nextflow way of doing it). 
* This allows for the output of each intermediate step to be analyzed post facto.
* That makes sense since this is an early stage experiment,
* but makes the code less clean and increases the storage required. A pipeline for this protocol,
* once it is more standardized, would avoid the extra code of saving those intermediate files 
* and just pass them directly into channels.
* See https://github.com/nextflow-io/rnatoy for an example pipeline where only the final file
* is saved to an output directory.
*/



def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/scisoseq --reads '*_R{1,2}.fastq.gz' -profile docker

    Mandatory arguments:
      --input                       Path to input data (must be surrounded with quotes)
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Options:
      --genome                      Name of iGenomes reference
      --singleEnd                   Specifies that the input is single end reads

    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta reference

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail               Same as --email, except only send mail if the workflow is not successful
      --maxMultiqcEmailFileSize     Theshold size for MultiQC report to be attached in notification email. If file generated by pipeline exceeds the threshold, it will not be attached (Default: 25MB)
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Check if genome exists in the config file
if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
    exit 1, "The provided genome '${params.genome}' is not available in the iGenomes file. Currently the available genomes are ${params.genomes.keySet().join(", ")}"
}

// TODO nf-core: Add any reference files that are needed
// Configurable reference genomes
//
// NOTE - THIS IS NOT USED IN THIS PIPELINE, EXAMPLE ONLY
// If you want to use the channel below in a process, define the following:
//   input:
//   file fasta from ch_fasta
//
params.ref_fasta = params.genome ? params.genomes[ params.genome ].fasta ?: false : false
params.ref_gtf = params.genome ? params.genomes[ params.genome ].gtf ?: false : false
params.intron_max = params.genome ? params.genomes[ params.genome ].intron_max ?: false : false
params.primers = params.primer_type ? params.primers_stets[ params.primer_type ].primer_file ?: false : false

if (params.fasta) { ch_fasta = file(params.fasta, checkIfExists: true) }

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
  custom_runName = workflow.runName
}

if ( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  // Check outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
  // Prevent trace files to be stored on S3 since S3 does not support rolling files.
  if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_multiqc_config = file(params.multiqc_config, checkIfExists: true)
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)

/*
 * Create a channel for input read files
if (params.input) {
    if (params.singleEnd) {
        Channel
            .from(params.input)
            .map { row -> [ row[0], [ file(row[1][0], checkIfExists: true) ] ] }
            .ifEmpty { exit 1, "params.input was empty - no input files supplied" }
            .into { read_files_fastqc; read_files_trimming }
    } else {
        Channel
            .from(params.input)
            .map { row -> [ row[0], [ file(row[1][0], checkIfExists: true), file(row[1][1], checkIfExists: true) ] ] }
            .ifEmpty { exit 1, "params.input was empty - no input files supplied" }
            .into { read_files_fastqc; read_files_trimming }
    }
} else {
    Channel
        .fromFilePairs( params.reads, size: params.singleEnd ? 1 : 2 )
        .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nNB: Path needs to be enclosed in quotes!\nIf this is single-end data, please specify --singleEnd on the command line." }
        .into { read_files_fastqc; read_files_trimming }
}

 */
Channel:
    .fromFilePairs(params.input + '*.ccs.{bam,bam.pbi}') { file -> file.name.replaceAll(/.ccs.bam$|.ccs.bam.pbi$/,'') }
    .ifEmpty { error "Cannot find matching bam and pbi files: $params.input. Make sure your bam files are pb indexed." }
    .set(ccs_out_indexed)
Channel
    .fromPath(params.input + '*.bam')
    .ifEmpty { error "Cannot find matching bam files: $params.input." }
    .tap { bam_files }

    // make a matching filename 'base' for every file
    .map{ file -> tuple(file.name.replaceAll(/.bam$/,''), file) } 
    .tap { bam_names }

Channel
    .fromPath(params.primers)
    .ifEmpty { error "Cannot find primer file: $params.primers" }
    .into { primers_remove; primers_refine } // puts the primer files into these two channels


Channel
    .fromPath(params.ref_fasta)
    .ifEmpty { error "Cannot find reference file: $params.ref_fasta" }
    .into {ref_fasta_align; ref_fasta_annotate}

Channel
    .fromPath(params.ref_gtf)
    .ifEmpty { error "Cannot find reference file: $params.ref_gtf"}
    .into {ref_gtf_annotate}



// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
summary['Reads']            = params.input
summary['Fasta Ref']        = params.fasta
summary['Data Type']        = params.singleEnd ? 'Single-End' : 'Paired-End'
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if (workflow.profile == 'awsbatch') {
  summary['AWS Region']     = params.awsregion
  summary['AWS Queue']      = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if (params.email || params.email_on_fail) {
  summary['E-mail Address']    = params.email
  summary['E-mail on failure'] = params.email_on_fail
  summary['MultiQC maxsize']   = params.maxMultiqcEmailFileSize
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-scisoseq-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/scisoseq Workflow Summary'
    section_href: 'https://github.com/nf-core/scisoseq'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}

/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
        saveAs: { filename ->
            if (filename.indexOf(".csv") > 0) filename
            else null
        }

    output:
    file 'software_versions_mqc.yaml' into software_versions_yaml
    file "software_versions.csv"

    script:
    // TODO nf-core: Get all tools to print their version number here
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    fastqc --version > v_fastqc.txt
    multiqc --version > v_multiqc.txt
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

/*
 * STEP 1 - FastQC
process fastqc {
    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/fastqc", mode: 'copy',
        saveAs: { filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename" }

    input:
    set val(name), file(reads) from read_files_fastqc

    output:
    file "*_fastqc.{zip,html}" into fastqc_results

    script:
    """
    fastqc --quiet --threads $task.cpus $reads
    """
}
 */

// Geoff: TODO: edit this for the primer design I used 
// Geoff: changed to use indexed .bam files (.pbi)
// Geoff: renamed demux which makes for sense for multiplexed samples
//        lima --ccs both demuxes and removes primers
//process remove_primers{
process demux{

    tag "primer removal: $name"

    publishDir "$params.outdir/$name/lima", mode: 'copy'

    input:
    // weird usage of dump - it is normally for debugging.
//    set name, file(bam) from ccs_out.dump(tag: 'ccs_name')
    set name, file(bam) from ccs_out_indexed
    path primers from primers_remove.collect()
    
    output:
    path "*"
    //set val(name), file("${name}.fl.primer_5p--primer_3p.bam") into primers_removed_out
    // TODO: get file output name
    set val(name), file("${name}.trimmed.bam") into trimmed_out 
 
//    """
//    lima $bam $primers ${name}.fl.bam --isoseq --no-pbi
//    """
    """
    lima --ccs $bam $primers ${name}.trimmed.bam
    """
}

process run_refine{

    tag "refining : $name"
    publishDir "$params.outdir/$name/refine", mode: 'copy'

    input:
    set name, file(bam) from trimmed_out.dump(tag: 'trimmed')
    path primers from primers_refine.collect()
    

    // flnc = full-length non-concatemer
    output:
    path "*"
    set val(name), file("${name}.flnc.fasta") into refine_out
    path "${name}.flnc.fasta" into refine_for_collapse
 
    //TODO update input & output channels
    """
    isoseq3 refine $bam $primers flnc.bam --require-polya
    bamtools convert -format fasta -in flnc.bam > ${name}.flnc.fasta
    """

}


// I am not sure whether the cluster and polish steps are necessary. The PacBio IsoSeq3
// page has them included but Liz Tseng's "best practices for single-cell IsoSeq" does not.
// As of v3.2, both clustering and polishing are performed by IsoSeq cluster
//process cluster_reads{

    //tag "clustering : $name"
    //publishDir "$params.outdir/$name/cluster", mode: 'copy'

    //input:
    //set name, file(refined) from refine_out.dump(tag: 'cluster')

    //output:
    //file "*"
    //set val(name), file("${name}.polished.fasta") into cluster_out
    //path "${name}.polished.fasta" into polished_for_collapse

    //"""
    //isoseq3 cluster ${refined} polished.bam
    //bamtools convert -format fasta -in polished.bam > ${name}.polished.fasta
    //"""
//}

// Following best practices here:
// https://github.com/Magdoll/cDNA_Cupcake/wiki/Best-practice-for-aligning-Iso-Seq-to-reference-genome:-minimap2,-deSALT,-GMAP,-STAR,-BLAT
process align_reads{

    tag "mapping : $name"

    // not clear if all files produced by the code or just the files specifid
    // in output are copied
    publishDir "$params.outdir/$name/minimap2", mode: 'copy'

    input:
   // set name, file(sample) from polish_out.dump(tag: 'align')
    //set name, file(polished_fasta) from cluster_out
    set name, file(flnc_fasta) from refine_out 
    path ref from ref_fasta_align

    output:    
    path "*.{sorted.sam,log}"
    set name, file("${name}.aln.sam") into align_out

    when:
    params.align

    """
    minimap2 $ref $flnc_fasta \
        -ax splice \
        -C5 \
        -O6,24 \
        -B4 \
        -uf \
        --secondary=no \
        -t ${task.cpus} > ${name}.aln.sam \
        2> ${name}.log

    """
}

// How does this process know to take only from the channels with a matching $name?
// For now it doesn't matter since I'm only dealing with one input file
// TODO: finish labeling output
// from https://github.com/Magdoll/cDNA_Cupcake/wiki/Cupcake:-supporting-scripts-for-Iso-Seq-after-clustering-step#collapse-redundant-isoforms-has-genome
process collapse_isoforms{

    publishDir "$params.outdir/$name/collapse_isoforms", mode: 'copy'


    input:
        set name, file(aligned_sam) from align_out
        path polished_fasta from polished_for_collapse

    output:
        path "*{gff,fq,txt}"
        set name, file("${name}.collapsed.rep.fq") into collapse_for_annotate
        set name, file("${name}.collapsed.rep.fq") into collapse_for_filter
        path "${name}.collapsed.group.txt" into collapse_for_filter


    // output is out.collapsed.gff, out.collapsed.rep.fq, out.collapsed.group.txt
    """
    sort -k 3,3 -k 4,4n $aligned_sam > sorted.sam
    collapse_isoforms_by_sam.py --input polished_fasta \
      -s sorted.sam -c 0.99 -i 0.95 -o ${name}

    """
}


/* This step performs correction and annotation of the reads according to a genome referece.
* The best docu is here: https://bitbucket.org/ConesaLab/sqanti/src/master/
* even though we are using the SQANTI2 pipeline for compatibility with the rest of the 
* PacBio recommended single cell pipeline https://github.com/Magdoll/SQANTI2#sqanti2
* There are several output files:
* name_corrected.fasta, the corrected LR sequences
* name_corrected.gtf, name_corrected.gff, name_corrected.sam, alignment of the corrected sequences
*  
*/
process correct_annotate{
     
    publishDir "$params.outdir/$name/sqanti_qc", mode: 'copy'

    input:
        set name, file(aligned_sam) from collapse_out
        path gtf_ref from ref_gtf
        path fasta_ref from ref_fasta_annotate


    output:
        path "*{fasta,gtf,sam,txt}"
        set name, file("${name}.sqanti_classification.txt") into classification_for_filter
        path "${name}.sqanti_corrected.fasta" into fasta_for_filter
        path "${name}.sqanti_corrected.gtf" into gtf_for_filter
        path "${name}.sqanti_corrected.sam" into sam_for_filter

    """
    python sqanti_qc2.py -t 30 $aligned_sam \
    $gtf_ref $fasta_ref

    mv *.fasta ${name}.sqanti_corrected.fasta
    mv *.gtf ${name}.sqanti_corrected.gtf
    mv *.sam ${name}.sqanti_corrected.sam
    mv *classication.txt ${name}.sqanti_classification.txt
    mv *junctions.txt ${name}.sqanti_junctions.txt
    """ 
}

/*
* This is the modified filter function, docs here https://github.com/Magdoll/SQANTI2#filtering-isoforms-using-sqanti2
* The output is not discussed in those docs but is mentioned here https://github.com/Magdoll/cDNA_Cupcake/wiki/Iso-Seq-Single-Cell-Analysis:-Recommended-Analysis-Guidelines#8-filter-artifacts
*/
process filter{

    publishDir "$params.outdir/$name/sqanti_filter", mode: 'copy'
    
    input:

        set name, file("${name}.sqanti_classification.txt") from classification_for_filter
        path fasta from fasta_for_filter
        path gtf   from gtf_for_filter
        path sam   from sam_for_filter

    output:
        path "*"

    """
    python sqanti_filter2.py \
     ${name}.sqanti_classification.txt \
     $fasta \
     $sam \
     $gtf

     mv *.fasta ${name}.sqanti_filtered.fasta
    """
}


/*
 * STEP 2 - MultiQC
process multiqc {
    publishDir "${params.outdir}/MultiQC", mode: 'copy'

    input:
    file multiqc_config from ch_multiqc_config
    // TODO nf-core: Add in log files from your new processes for MultiQC to find!
    file ('fastqc/*') from fastqc_results.collect().ifEmpty([])
    file ('software_versions/*') from software_versions_yaml.collect()
    file workflow_summary from create_workflow_summary(summary)

    output:
    file "*multiqc_report.html" into multiqc_report
    file "*_data"
    file "multiqc_plots"

    script:
    rtitle = custom_runName ? "--title \"$custom_runName\"" : ''
    rfilename = custom_runName ? "--filename " + custom_runName.replaceAll('\\W','_').replaceAll('_+','_') + "_multiqc_report" : ''
    // TODO nf-core: Specify which MultiQC modules to use with -m for a faster run time
    """
    multiqc -f $rtitle $rfilename --config $multiqc_config .
    """
}

/*
 * STEP 3 - Output Description HTML
process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    file output_docs from ch_output_docs

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.r $output_docs results_description.html
    """
}
 */

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/scisoseq] Successful: $workflow.runName"
    if (!workflow.success) {
      subject = "[nf-core/scisoseq] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if (workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // TODO nf-core: If not using MultiQC, strip out this code (including params.maxMultiqcEmailFileSize)
    // On success try attach the multiqc report
    def mqc_report = null
    try {
        if (workflow.success) {
            mqc_report = multiqc_report.getVal()
            if (mqc_report.getClass() == ArrayList) {
                log.warn "[nf-core/scisoseq] Found multiple reports from process 'multiqc', will use only one"
                mqc_report = mqc_report[0]
            }
        }
    } catch (all) {
        log.warn "[nf-core/scisoseq] Could not attach MultiQC report to summary email"
    }

    // Check if we are only sending emails on failure
    email_address = params.email
    if (!params.email && params.email_on_fail && !workflow.success) {
        email_address = params.email_on_fail
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.maxMultiqcEmailFileSize.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (email_address) {
        try {
          if ( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/scisoseq] Sent summary e-mail to $email_address (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, email_address ].execute() << email_txt
          log.info "[nf-core/scisoseq] Sent summary e-mail to $email_address (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/pipeline_info/" )
    if (!output_d.exists()) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
      log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
      log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}"
      log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}"
    }

    if (workflow.success) {
        log.info "${c_purple}[nf-core/scisoseq]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[nf-core/scisoseq]${c_red} Pipeline completed with errors${c_reset}"
    }

}


def nfcoreHeader(){
    // Log colors ANSI codes
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";

    return """    -${c_dim}--------------------------------------------------${c_reset}-
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  nf-core/scisoseq v${workflow.manifest.version}${c_reset}
    -${c_dim}--------------------------------------------------${c_reset}-
    """.stripIndent()
}

def checkHostname(){
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}
