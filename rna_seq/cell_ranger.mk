include weigelt-lab/Makefile.inc

LOGDIR = log/cell_ranger.$(NOW)

cellranger : $(foreach sample,$(SAMPLES),cellranger/$(sample)/outs/web_summary.html)

CELLRANGER_THREADS ?= 16
CELLRANGER_MEM_THREAD ?= 5G
CELLRANGER_WALL_TIME ?= 48:00:00

CELLRANGER_REF ?= $(HOME)/share/lib/ref_files/10X/refdata-gex-GRCh38-2024-A

PROJECT_DIR := $(notdir $(CURDIR))

comma := ,
space := $(empty) $(empty)

define cellranger-count
cellranger/$1/outs/web_summary.html : $$(foreach split,$2,$$(fq.$$(split)))
	$$(call RUN,-c -n $(CELLRANGER_THREADS) -s 3G -m $(CELLRANGER_MEM_THREAD) -p $(PROJECT_DIR)/cellranger -N $1 -v $(CELLRANGER_ENV) -w $(CELLRANGER_WALL_TIME),"set -o pipefail && \
																																								  mkdir -p cellranger/$1 && \
																																								  cd cellranger && \
																																								  cellranger count \
																																								  --id=$1 \
																																								  --transcriptome=$(CELLRANGER_REF) \
																																								  --fastqs=$$(subst $$(space),$$(comma),$$(abspath $$(sort $$(dir $$(foreach split,$2,$$(fq.$$(split))))))) \
																																								  --sample=$1 \
																																								  --create-bam=true \
																																								  --localcores=$(CELLRANGER_THREADS) \
																																								  --localmem=64")

endef
$(foreach sample,$(SAMPLES),\
        $(eval $(call cellranger-count,$(sample),$(split.$(sample)))))
        
..DUMMY := $(shell mkdir -p version; \
	~/share/env/cellranger-10.1.0/opt/cellranger-10.1.0/cellranger --version >> version/cell_ranger.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: cellranger clean

clean:
