include weigelt-lab/Makefile.inc

LOGDIR = log/cell_ranger.$(NOW)

cellranger : $(foreach sample,$(SAMPLES),cellranger/$(sample)/outs/web_summary.html)

PROJECT_DIR := $(notdir $(CURDIR))

comma := ,
space := $(empty) $(empty)

define cellranger-count
cellranger/$1/outs/web_summary.html : $$(foreach split,$2,$$(fq.$$(split)))
	$$(call RUN,-c -n 16 -s 4G -m 5G -p $(PROJECT_DIR)/star -N $1/cellranger -v $(CELLRANGER_ENV) -w 48:00:00,"set -o pipefail && \
																											   mkdir -p cellranger && \
																											   cd cellranger && \
																											   cellranger count \
																											   --id=$1 \
																											   --transcriptome=$(CELLRANGER_REF) \
																											   --fastqs=$$(subst $$(space),$$(comma),$$(abspath $$(sort $$(dir $$(foreach split,$2,$$(fq.$$(split))))))) \
																											   --sample=$1 \
																											   --create-bam=true \
																											   --localcores=16 \
																											   --localmem=64")
endef
$(foreach sample,$(SAMPLES),\
        $(eval $(call cellranger-count,$(sample),$(split.$(sample)))))
        
..DUMMY := $(shell mkdir -p version; \
	~/share/env/cellranger-10.1.0/bin/cellranger --version >> version/cell_ranger.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: cellranger clean

clean:
