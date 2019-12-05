FROM nfcore/base:1.7
LABEL authors="Geoff Stanley" \
      description="Docker image containing all requirements for nf-core/scisoseq pipeline"

RUN apt-get update
COPY environment.yml /
ENV PATH /opt/conda/envs/nf-core-scisoseq-1.0dev/bin:$PATH
RUN conda env create -f /environment.yml && conda clean -a

# From https://github.com/docker-library/python/issues/60 
#RUN apt-get install -y --no-install-recommends gcc \
RUN apt-get install -y gcc --fix-missing
##    && apt-get purge -y --auto-remove gcc 
# the --no-install-recommends helps limit some of the install so that you can be more explicit about what gets installed
# Install cDNA_Cupcake and add some of the packages 
RUN cd /home && \
    git clone https://github.com/Magdoll/cDNA_Cupcake.git && \
    cd cDNA_Cupcake && \
    git checkout Py2_v8.7.x && \
    python setup.py build && \
    python setup.py install
 
ENV PYTHONPATH /home/cDNA_Cupcake/sequence:$PYTHONPATH

