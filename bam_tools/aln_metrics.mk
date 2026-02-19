include weigelt-lab/Makefile.inc

LOGDIR ?= log/aln_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).aln_metrics.txt) \
	  summary/aln_metrics.txt
	 
TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.aln_metrics.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/aln_metrics,"set -o pipefail && \
										      $$(COLLECT_ALIGNMENT_METRICS) \
										      REFERENCE_SEQUENCE=$$(REF_FASTA) \
										      INPUT=$$(<) \
										      OUTPUT=$$(@)")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/aln_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).aln_metrics.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/aln,"set -o pipefail && \
										  $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 2 --sample_names '$(SAMPLES)'")
					  
..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/aln_metrics.txt; \
	R --version >> version/aln_metrics.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: metrics