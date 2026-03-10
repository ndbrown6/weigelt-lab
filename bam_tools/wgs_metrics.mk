include weigelt-lab/Makefile.inc

LOGDIR ?= log/wgs_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).wgs_metrics.txt) \
		  summary/wgs_metrics.txt

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.wgs_metrics.txt : bam/$1.bam
	$$(call RUN,-c -n 1 -s 12G -m 24G -w 24:00:00 -p $(PROJECT_DIR)/metrics -N $1/wgs_metrics,"set -o pipefail && \
																							   $$(COLLECT_WGS_METRICS) \
																							   INPUT=$$(<) \
																							   OUTPUT=$$(@) \
																							   REFERENCE_SEQUENCE=$$(REF_FASTA)")
                            
endef
$(foreach sample,$(SAMPLES),\
    $(eval $(call picard-metrics,$(sample))))

summary/wgs_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).wgs_metrics.txt)
	$(call RUN,-c -n 1 -s 8G -m 12G -p $(PROJECT_DIR)/summary -N metrics/wgs,"set -o pipefail && \
																			  $(RSCRIPT) $(SCRIPTS_DIR)/summary/wgs_metrics.R \
																			  --option 6 \
																			  --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/wgs_metrics.txt; \
	R --version >> version/wgs_metrics.txt)	
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: metrics