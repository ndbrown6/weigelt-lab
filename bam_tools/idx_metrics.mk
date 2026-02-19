include weigelt-lab/Makefile.inc

LOGDIR ?= log/idx_metrics.$(NOW)

metrics : $(foreach sample,$(SAMPLES),metrics/$(sample).idx_stats.txt) \
	  summary/idx_metrics.txt
	 
TARGETS_LIST := $(TARGETS_FILE:.bed=.list)
BAITS_LIST := $(BAITS_FILE:.bed=.list)

PROJECT_DIR := $(notdir $(CURDIR))

define picard-metrics
metrics/$1.idx_stats.txt : bam/$1.bam
	$$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/metrics -N $1/idx_stats,"set -o pipefail && \
										    $$(BAM_INDEX) \
										    INPUT=$$(<) \
										    > $$(@)")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call picard-metrics,$(sample))))
	
summary/idx_metrics.txt : $(foreach sample,$(SAMPLES),metrics/$(sample).idx_stats.txt)
	$(call RUN, -c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/summary -N summary/idx,"set -o pipefail && \
										  $(RSCRIPT) $(SCRIPTS_DIR)/summary/bam_metrics.R --option 1 --sample_names '$(SAMPLES)'")
					  
..DUMMY := $(shell mkdir -p version; \
	echo "picard" >> version/idx_metrics.txt; \
	R --version >> version/idx_metrics.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: metrics