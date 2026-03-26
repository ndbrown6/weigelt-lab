include weigelt-lab/Makefile.inc
include weigelt-lab/config/arriba.inc

LOGDIR ?= log/star_fusion.$(NOW)

call_fusions : $(foreach sample,$(SAMPLES),starfusion/$(sample)/fusions.tsv)
smry_fusions : starfusion/fusion_summary.txt
draw_fusions : $(foreach sample,$(SAMPLES),starfusion/$(sample)/fusions.pdf)

smry : call_fusions \
	   smry_fusions \
	   draw_fusions
	      
STAR_THREADS ?= 4
STAR_MEM_THREAD ?= 15G
STAR_WALL_TIME ?= 36:00:00

SAMTOOLS_THREADS ?= 8
SAMTOOLS_MEM_THREAD ?= 2G

CTAT_LIB ?= $(HOME)/share/lib/ref_files/CTAT_GRCh37/GRCh37_gencode_v19_CTAT_lib_Apr032020/ctat_genome_lib_build_dir/

PROJECT_DIR := $(notdir $(CURDIR))

define merge-fastq
starfusion/$1/$1_R1.fastq : $$(foreach split,$2,$$(word 1, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 1G -m 2G -w 12:00:00 -v $(PIGZ_ENV) -p $(PROJECT_DIR)/starfusion -N $1/merge_R1,"set -o pipefail && \
																											mkdir -p starfusion/$1 && \
																											pigz -cd $$(^) > $$(@)")
    
starfusion/$1/$1_R2.fastq : $$(foreach split,$2,$$(word 2, $$(fq.$$(split))))
	$$(call RUN,-c -n 1 -s 1G -m 2G -w 12:00:00 -v $(PIGZ_ENV) -p $(PROJECT_DIR)/starfusion -N $1/merge_R2,"set -o pipefail && \
																											mkdir -p starfusion/$1 && \
																											pigz -cd $$(^) > $$(@)")
endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call merge-fastq,$(sample),$(split.$(sample)))))


define star-fusion
starfusion/$1/fusions.tsv : starfusion/$1/$1_R1.fastq starfusion/$1/$1_R2.fastq
	$$(call RUN,-n $(STAR_THREADS) -s 1G -m $(STAR_MEM_THREAD) -p $(PROJECT_DIR)/starfusion -N $1/STAR -v $(STARFUSION_ENV) -w $(STAR_WALL_TIME),"set -o pipefail && \
																																			      STAR-Fusion \
																																			      --left_fq $$(<) \
																																			      --right_fq $$(<<) \
																																			      --CPU $$(STAR_THREADS) \
																																			      --output_dir starfusion/$1 \
																																			      --genome_lib_dir $$(CTAT_LIB) && \
																																			      mv starfusion/$1/star-fusion.fusion_predictions.abridged.tsv $$(@) && \
																																			      mv starfusion/$1/star-fusion.fusion_predictions.tsv starfusion/$1/predictions.tsv")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call star-fusion,$(sample))))

define draw-fusions	
starfusion/$1/fusions.txt : starfusion/$1/fusions.tsv
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/starfusion -N $1/reformat,"set -o pipefail && \
																				 $$(RSCRIPT) $(SCRIPTS_DIR)/summary/starfusion_summary.R \
																				 --option 1 \
																				 --sample_names $1 \
																				 --ensembl $(HOME)/share/lib/resource_files/Hugo_ENST_ensembl75_fixed.txt")
																						 																																			      
starfusion/$1/Aligned.sortedByCoord.out.bam : starfusion/$1/fusions.txt
	$$(call RUN,-c -n $(SAMTOOLS_THREADS) -s 1G -m $(SAMTOOLS_MEM_THREAD) -p $(PROJECT_DIR)/starfusion -N $1/sort,"set -o pipefail && \
																												   samtools sort \
																												   -@ $(SAMTOOLS_THREADS) \
																												   -m $(SAMTOOLS_MEM_THREAD) \
																												   -o $$(@) \
																												   starfusion/$1/Aligned.out.bam && \
																												   samtools index $$(@)")

starfusion/$1/fusions.pdf : starfusion/$1/fusions.txt starfusion/$1/Aligned.sortedByCoord.out.bam
	$$(call RUN,-c -n 1 -s 12G -m 24G -p $(PROJECT_DIR)/starfusion -N $1/draw_fusions -v $(GENOMIC_ALIGNMENTS_ENV),"set -o pipefail && \
    																											    $$(RSCRIPT) $$(DRAW_FUSIONS) \
																												    --fusions=$$(<) \
																												    --annotation=$$(ANNOTATION_GTF) \
																												    --alignments=$$(<<) \
																												    --cytobands=$$(CYTOBAND) \
																												    --proteinDomains=$$(PROTEIN_DOMAINS_GFF3) \
																												    --output=$$(@)")

endef
$(foreach sample,$(SAMPLES),\
	$(eval $(call draw-fusions,$(sample))))
		
starfusion/fusion_summary.txt : $(foreach sample,$(SAMPLES),starfusion/$(sample)/fusions.tsv)
	$(call RUN, -c -n 1 -s 16G -m 24G -p $(PROJECT_DIR)/starfusion -N summary,"set -o pipefail && \
																			   $(RSCRIPT) $(SCRIPTS_DIR)/summary/starfusion_summary.R \
																			   --option 2 \
																			   --sample_names '$(SAMPLES)'")

..DUMMY := $(shell mkdir -p version; \
	$(STARFUSION_ENV)/bin/STAR-Fusion --version &> version/star_fusion.txt)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: call_fusions smry_fusions draw_fusions smry clean

clean : 
	rm -f starfusion/*/*.fastq && \
	rm -f starfusion/*/*.bam* && \
	rm -f starfusion/*/*.cmds && \
	rm -f starfusion/*/*.out && \
	rm -f starfusion/*/*.tab && \
	rm -f starfusion/*/*.junction && \
	rm -f starfusion/*/*.txt && \
	rm -rf starfusion/*/_starF_checkpoints && \
	rm -rf starfusion/*/star-fusion.preliminary && \
	rm -rf starfusion/*/_STARgenome && \
	rm -rf starfusion/*/_STARpass1
