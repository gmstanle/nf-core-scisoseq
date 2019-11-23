FROM nfcore/base:1.7
LABEL authors="Geoff Stanley" \
      description="Docker image containing all requirements for nf-core/scisoseq pipeline"

COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a
ENV PATH /opt/conda/envs/nf-core-scisoseq-1.0dev/bin:$PATH
