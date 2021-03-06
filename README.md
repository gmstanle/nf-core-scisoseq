# ![nf-core/scisoseq](docs/images/nf-core-scisoseq_logo.png)

**workflow for single-cell pacbio long-read data**.

[![Build Status](https://travis-ci.com/nf-core/scisoseq.svg?branch=master)](https://travis-ci.com/nf-core/scisoseq)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A50.32.0-brightgreen.svg)](https://www.nextflow.io/)

[![install with bioconda](https://img.shields.io/badge/install%20with-bioconda-brightgreen.svg)](http://bioconda.github.io/)
[![Docker](https://img.shields.io/docker/automated/gmstanle/scisoseq.svg)](https://hub.docker.com/r/gmstanle/scisoseq)

## Introduction

This pipeline is intended to demultiplex and align PacBio CCS reads from single cells using the [IsoSeq3 pipeline](https://github.com/PacificBiosciences/IsoSeq) and the guidelines developed by Liz Tseng ([here](https://github.com/Magdoll/cDNA_Cupcake/wiki/Iso-Seq-Single-Cell-Analysis:-Recommended-Analysis-Guidelines)). This pipeline is currently modified to align cDNA that has dual barcodes, one on either end of the read, and no UMIs. It produces a .csv file in the `collate/` results folder that has the isoform id, ccs, and the identity of the top-matching barcode for either end.

The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It comes with docker containers making installation trivial and results highly reproducible.

## Quick Start

i. Install [`nextflow`](https://nf-co.re/usage/installation)

ii. Install one of [`docker`](https://docs.docker.com/engine/installation/), [`singularity`](https://www.sylabs.io/guides/3.0/user-guide/) or [`conda`](https://conda.io/miniconda.html)

iii. Download the pipeline and test it on a minimal dataset with a single command

```bash
nextflow run nf-core/scisoseq -profile test,<docker/singularity/conda>
```

iv. Start running your own analysis!

<!-- TODO nf-core: Update the default command above used to run the pipeline -->
```bash
nextflow run nf-core/scisoseq -profile <docker/singularity/conda> --input 'data/*.bam' --genome GRCm38
```
https://camo.githubusercontent.com/379552643323a9b9a6c5d3fcaaf4f305e4a6327e/68747470733a2f2f6875622e646f636b65722e636f6d2f722f676d7374616e6c652f736369736f736571

See [usage docs](docs/usage.md) for all of the available options when running the pipeline.

## Documentation

The nf-core/scisoseq pipeline comes with documentation about the pipeline, found in the `docs/` directory:

1. [Installation](https://nf-co.re/usage/installation)
2. Pipeline configuration
    * [Local installation](https://nf-co.re/usage/local_installation)
    * [Adding your own system config](https://nf-co.re/usage/adding_own_config)
    * [Reference genomes](https://nf-co.re/usage/reference_genomes)
3. [Running the pipeline](docs/usage.md)
4. [Output and how to interpret the results](docs/output.md)
5. [Troubleshooting](https://nf-co.re/usage/troubleshooting)

<!-- TODO nf-core: Add a brief overview of what the pipeline does and how it works -->

## Credits

nf-core/scisoseq was originally written by [Geoff Stanley](https://github.com/gmstanle/).

## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](.github/CONTRIBUTING.md).

For further information or help, don't hesitate to get in touch on [Slack](https://nfcore.slack.com/channels/nf-core/scisoseq) (you can join with [this invite](https://nf-co.re/join/slack)).

## Citation

<!-- TODO nf-core: Add citation for pipeline after first release. Uncomment lines below and update Zenodo doi. -->
<!-- If you use  nf-core/scisoseq for your analysis, please cite it using the following doi: [10.5281/zenodo.XXXXXX](https://doi.org/10.5281/zenodo.XXXXXX) -->

You can cite the `nf-core` pre-print as follows:  
Ewels PA, Peltzer A, Fillinger S, Alneberg JA, Patel H, Wilm A, Garcia MU, Di Tommaso P, Nahnsen S. **nf-core: Community curated bioinformatics pipelines**. *bioRxiv*. 2019. p. 610741. [doi: 10.1101/610741](https://www.biorxiv.org/content/10.1101/610741v1).

The packages used herein were largely developed by Pacific Biosciences ([Isoseq](https://github.com/PacificBiosciences/IsoSeq)), [Elizabeth Tseng](https://github.com/Magdoll) (SQANTI2), and the [Conesa lab](https://github.com/ConesaLab) (SQANTI).

I have packaged them into a convenient NextFlow pipeline with Docker so that they can be easily run on any cloud service, private server cluster, or local machine. 
