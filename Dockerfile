FROM nfcore/base:1.7
LABEL authors="Geoff Stanley" \
      description="Docker image containing all requirements for nf-core/scisoseq pipeline"

COPY environment.yml /
ENV PATH /opt/conda/envs/nf-core-scisoseq-1.0dev/bin:$PATH
RUN conda env create -f /environment.yml && conda clean -a

# Install cDNA_Cupcake and add some of the packages 
RUN cd /home && \
    git clone https://github.com/Magdoll/cDNA_Cupcake.git && \
    git checkout Py2_v8.7.x && \
    cd cDNA_Cupcake && \
    python setup.py build && \
    python setup.py install
 
ENV PYTHONPATH /home/cDNA_Cupcake/sequence:$PYTHONPATH
