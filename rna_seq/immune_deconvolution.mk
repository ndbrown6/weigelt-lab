include weigelt-lab/Makefile.inc

LOGDIR = log/immune_deconvolution.$(NOW)

immune : immune_deconvolution/quantiseq.txt \
         immune_deconvolution/mcpcounter.txt \
         immune_deconvolution/cibersort.txt

KALLISTO_MAKEFILE ?= weigelt-lab/rna_seq/kallisto_quant.mk

PROJECT_DIR := $(notdir $(CURDIR))

kallisto/tpm_bygene.txt : ; +$(MAKE) -f $(KALLISTO_MAKEFILE) kallisto

immune_deconvolution/quantiseq.txt : kallisto/tpm_bygene.txt
	$(call RUN, -c -n 1 -s 8G -m 16G -v $(IMMUNE_ENV) -p $(PROJECT_DIR)/immune_deconv -N quantiseq,"set -o pipefail && \
																									$(RSCRIPT) $(SCRIPTS_DIR)/rna_seq/immune_deconvolution.R \
																									--option 1 \
																									--input_file $(<) \
																									--output_file $(@)")

immune_deconvolution/mcpcounter.txt : kallisto/tpm_bygene.txt
	$(call RUN, -c -n 1 -s 8G -m 16G -v $(IMMUNE_ENV) -p $(PROJECT_DIR)/immune_deconv -N mcpcounter,"set -o pipefail && \
																									 $(RSCRIPT) $(SCRIPTS_DIR)/rna_seq/immune_deconvolution.R \
																									 --option 2 \
																									 --input_file $(<) \
																									 --output_file $(@)")

immune_deconvolution/cibersort.txt : kallisto/tpm_bygene.txt
	$(call RUN, -c -n 1 -s 8G -m 16G -v $(IMMUNE_ENV) -p $(PROJECT_DIR)/immune_deconv -N cibersort,"set -o pipefail && \
																									$(RSCRIPT) $(SCRIPTS_DIR)/rna_seq/immune_deconvolution.R \
																									--option 3 \
																									--input_file $(<) \
																									--output_file $(@)")

..DUMMY := $(shell mkdir -p version; \
	~/share/env/r-immunedeconv-2.1.0/bin/R --version >> version/immune_deconvolution.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	+$(MAKE) -f $(KALLISTO_MAKEFILE) clean