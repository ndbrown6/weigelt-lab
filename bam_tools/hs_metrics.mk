include weigelt-lab/Makefile.inc

LOGDIR ?= log/hs_metrics.$(NOW)

bwamem : $(foreach sample,$(SAMPLES),metrics/$(sample).hs_metrics.txt) \
	 summary/hs_metrics.txt
	 
TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.hs_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/hs_metrics,"set -o pipefail && \
										     $$(COLLECT_HS_METRICS) \
										     REFERENCE_SEQUENCE=$$(REF_FASTA) \
										     INPUT=$$(<) \
										     OUTPUT=$$(@) \
										     BAIT_INTERVALS=$$(BAITS_LIST) \
										     TARGET_INTERVALS=$$(TARGETS_LIST)")
							
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/hs_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).hs_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/hs,"set -o pipefail && \
										 $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 6 --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	     echo "picard" >> version/hs_metrics.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: