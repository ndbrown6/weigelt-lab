include weigelt-lab/Makefile.inc

LOGDIR = log/cell_ranger.$(NOW)

count : $(foreach sample,$(SAMPLES),cellranger/$(sample)/timestamp.count.txt)
multi: $(foreach sample,$(SAMPLES),cellranger/$(sample)/$(sample).RData)

CELLRANGER_THREADS ?= 16
CELLRANGER_MEM_THREAD ?= 5G
CELLRANGER_WALL_TIME ?= 48:00:00
CELLRANGER_REF ?= $(HOME)/share/lib/ref_files/10X/refdata-gex-GRCh38-2024-A

PROJECT_DIR := $(notdir $(CURDIR))

comma := ,
space := $(empty) $(empty)
fq_prefix = $(shell for f in $(foreach s,$(split.$(1)),$(fq.$(s))); do basename $$f; done \
            | sed -E 's/_S[0-9]+_L[0-9]+_[RI][12]_001\.fastq\.gz$$//' | sort -u | paste -sd, -)

define cellranger-count
cellranger/$1/timestamp.count.txt : $$(foreach split,$2,$$(fq.$$(split)))
	$$(call RUN,-n $(CELLRANGER_THREADS) -s 3G -m $(CELLRANGER_MEM_THREAD) -p $(PROJECT_DIR)/cellranger -N count/$1 -v $(CELLRANGER_ENV) -w $(CELLRANGER_WALL_TIME),"set -o pipefail && \
																																									 mkdir -p cellranger && \
																																									 cd cellranger && \
																																									 rm -rf $1 2>/dev/null || true && \
																																									 cellranger count \
																																									 --id=$1 \
																																									 --transcriptome=$(CELLRANGER_REF) \
																																									 --fastqs=$$(subst $$(space),$$(comma),$$(abspath $$(sort $$(dir $$(foreach split,$2,$$(fq.$$(split))))))) \
																																									 --sample=$$(call fq_prefix,$1) \
																																									 --create-bam=true \
																																									 --localcores=$(CELLRANGER_THREADS) \
																																									 --localmem=64 && \
																																									 touch timestamp.count.txt")

endef
$(foreach sample,$(SAMPLES),\
        $(eval $(call cellranger-count,$(sample),$(split.$(sample)))))
        
define cellranger-multi
cellranger/$1/timestamp.multi.txt : $$(foreach split,$2,$$(fq.$$(split)))
	$$(call RUN,-n $(CELLRANGER_THREADS) -s 3G -m $(CELLRANGER_MEM_THREAD) -p $(PROJECT_DIR)/cellranger -N multi/$1 -v $(CELLRANGER_ENV) -w $(CELLRANGER_WALL_TIME),"set -o pipefail && \
																																									 mkdir -p cellranger && \
																																									 cd cellranger && \
																																									 rm -rf $1 2>/dev/null || true && \
																																									 cellranger multi \
																																									 --id=$1 \
																																									 --csv=../config/config.csv \
																																									 --localcores=$(CELLRANGER_THREADS) \
																																									 --localmem=64 && \
																																									 touch timestamp.multi.txt")
																																									 
cellranger/$1/$1.RData : cellranger/$1/timestamp.multi.txt
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/cellranger -N summarize/$1 -v $(SEURAT_ENV),"set -o pipefail && \
																									 cd cellranger/$1 && \
																									 $(RSCRIPT) $(SCRIPTS_DIR)/rna_seq/summarize_cellranger.R \
																									 --option 2 \
																									 --sample_name $1 \
																									 --out_file $$(@)")

endef
$(foreach sample,$(SAMPLES),\
        $(eval $(call cellranger-multi,$(sample),$(split.$(sample)))))
        
..DUMMY := $(shell mkdir -p version; \
	~/share/env/cellranger-10.1.0/opt/cellranger-10.1.0/cellranger --version >> version/cell_ranger.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: count multi clean

clean:
	rm -f cellranger/*/timestamp.*.txt
