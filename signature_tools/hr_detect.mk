include weigelt-lab/Makefile.inc

LOGDIR ?= log/hr_detect.$(NOW)

smry :  $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).png) \
	    $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).svg) \
		hr_detect/hrdetect_summary.txt \
		hr_detect/signatures_summary.txt
		     
PROJECT_DIR := $(notdir $(CURDIR))

MIN_SIZE = 1
MAX_SIZE = 100000000000000000000

define hr-detect-snv
hr_detect/$1_$2/$1_$2.snv.vcf : summary/tsv/all.tsv
	$$(call RUN,-c -n 1 -s 12G -m 16G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/snv/maf2vcf -N $1/$2,"set -o pipefail && \
																										mkdir -p hr_detect/$1_$2/ && \
																						   			    $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																									    --option 1 \
																									    --sample_name $1_$2")

hr_detect/$1_$2/$1_$2.snv.vcf.bgz : hr_detect/$1_$2/$1_$2.snv.vcf
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/snv/bgzip -N $1/$2,"set -o pipefail && \
																			bgzip -c $$(<) > $$(@)")

hr_detect/$1_$2/$1_$2.snv.vcf.bgz.tbi : hr_detect/$1_$2/$1_$2.snv.vcf.bgz
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/snv/tabix -N $1/$2,"set -o pipefail && \
																			tabix -p vcf $$(<)")

hr_detect/$1_$2/$1_$2.snv.fix.vcf : hr_detect/$1_$2/$1_$2.snv.vcf.bgz hr_detect/$1_$2/$1_$2.snv.vcf.bgz.tbi
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/snv/fix/unzip -N $1/$2,"set -o pipefail && \
																		  		bcftools view $$(<) > $$(@)")
								
hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz : hr_detect/$1_$2/$1_$2.snv.fix.vcf
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/snv/fix/bgzip -N $1/$2,"set -o pipefail && \
																				bgzip -c $$(<) > $$(@)")

hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz.tbi : hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/snv/fix/tabix -N $1/$2,"set -o pipefail && \
																				tabix -p vcf $$(<)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call hr-detect-snv,$(tumor.$(pair)),$(normal.$(pair)))))

define hr-detect-indel
hr_detect/$1_$2/$1_$2.indel.vcf : summary/tsv/all.tsv
	$$(call RUN,-c -n 1 -s 12G -m 16G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/indel/maf2vcf -N $1/$2,"set -o pipefail && \
																										  mkdir -p hr_detect/$1_$2/ && \
																									      $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																									      --option 2 \
																									      --sample_name $1_$2")
								     
hr_detect/$1_$2/$1_$2.indel.vcf.bgz : hr_detect/$1_$2/$1_$2.indel.vcf
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/indel/bgzip -N $1/$2,"set -o pipefail && \
																			  bgzip -c $$(<) > $$(@)")

hr_detect/$1_$2/$1_$2.indel.vcf.bgz.tbi : hr_detect/$1_$2/$1_$2.indel.vcf.bgz
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/indel/tabix -N $1/$2,"set -o pipefail && \
																			  tabix -p vcf $$(<)")
								
hr_detect/$1_$2/$1_$2.indel.fix.vcf : hr_detect/$1_$2/$1_$2.indel.vcf.bgz hr_detect/$1_$2/$1_$2.indel.vcf.bgz.tbi
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/indel/fix/unzip -N $1/$2,"set -o pipefail && \
																				  bcftools view $$(<) > $$(@)")

hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz : hr_detect/$1_$2/$1_$2.indel.fix.vcf
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/indel/fix/bgzip -N $1/$2,"set -o pipefail && \
																				  bgzip -c $$(<) > $$(@)")

hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz.tbi : hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz
	$$(call RUN,-c -n 1 -s 12G -m 16G -p $(PROJECT_DIR)/indel/fix/tabix -N $1/$2,"set -o pipefail && \
																				  tabix -p vcf $$(<)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call hr-detect-indel,$(tumor.$(pair)),$(normal.$(pair)))))

define hr-detect-sv
hr_detect/$1_$2/$1_$2.merged.bed : vcf/$1_$2.merged_sv.vcf
	$$(call RUN,-c -n 1 -s 4G -m 8G -v $(SURVIVOR_ENV) -p $(PROJECT_DIR)/vcf2bed -N $1/$2,"set -o pipefail && \
																						   mkdir -p hr_detect/$1_$2/ && \
																						   SURVIVOR vcftobed \
																						   $$(<) \
																						   $(MIN_SIZE) \
																						   $(MAX_SIZE) \
																						   $$(@)")
							    
hr_detect/$1_$2/$1_$2.merged.bedpe : hr_detect/$1_$2/$1_$2.merged.bed
	$$(call RUN,-c -n 1 -s 4G -m 8G -p $(PROJECT_DIR)/bed2bedpe -N $1/$2,"set -o pipefail && \
																		  echo \"chrom1	start1	end1	chrom2	start2	end2	sv_id	pe_support	strand1	strand2	svclass\" > \
																		  $$(@) && \
																		  cat $$(<) >> $$(@)")
					 
hr_detect/$1_$2/$1_$2.sv.bedpe : hr_detect/$1_$2/$1_$2.merged.bedpe
	$$(call RUN,-c -n 1 -s 12G -m 16G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/bedpe2bedpe -N $1/$2,"set -o pipefail && \
																									    $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																									    --option 3 \
																									    --sample_name $1_$2")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call hr-detect-sv,$(tumor.$(pair)),$(normal.$(pair)))))

define hr-detect-cn																									    								
hr_detect/$1_$2/$1_$2.cn.txt : facets/cncf/$1_$2.txt
	$$(call RUN,-c -n 1 -s 12G -m 16G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/facets -N $1/$2,"set -o pipefail && \
																								   mkdir -p hr_detect/$1_$2/ && \
																								   $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																								   --option 4 \
																								   --sample_name $1_$2")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call hr-detect-cn,$(tumor.$(pair)),$(normal.$(pair)))))																								   


define hr-detect-plot								     
hr_detect/$1_$2/$1_$2.png : hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz \
							hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz.tbi \
							hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz \
							hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz.tbi \
							hr_detect/$1_$2/$1_$2.sv.bedpe \
							hr_detect/$1_$2/$1_$2.cn.txt
	$$(call RUN,-c -n 1 -s 12G -m 16G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/plot/png -N $1/$2,"set -o pipefail && \
																								     $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																								     --option 5 \
																								     --sample_name $1_$2 && \
																								     mv hr_detect/$1_$2/$1_$2.genomePlot.png $$(@)")

hr_detect/$1_$2/$1_$2.svg : hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz \
							hr_detect/$1_$2/$1_$2.snv.fix.vcf.bgz.tbi \
							hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz \
							hr_detect/$1_$2/$1_$2.indel.fix.vcf.bgz.tbi \
							hr_detect/$1_$2/$1_$2.sv.bedpe \
							hr_detect/$1_$2/$1_$2.cn.txt
	$$(call RUN,-c -n 1 -s 12G -m 16G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/plot/svg -N $1/$2,"set -o pipefail && \
																								     $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																								     --option 6 \
																								     --sample_name $1_$2 && \
																								     mv hr_detect/$1_$2/$1_$2.genomePlot.svg $$(@)")

endef
$(foreach pair,$(SAMPLE_PAIRS),\
		$(eval $(call hr-detect-plot,$(tumor.$(pair)),$(normal.$(pair)))))
		
hr_detect/hrdetect_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).snv.fix.vcf.bgz) \
								 $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).snv.fix.vcf.bgz.tbi) \
								 $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).indel.fix.vcf.bgz) \
								 $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).indel.fix.vcf.bgz.tbi) \
								 $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).sv.bedpe) \
								 $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).cn.txt)
	$(call RUN, -c -n 4 -s 6G -m 9G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/summary -N hrdetect,"set -o pipefail && \
																						  			 $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																						  			 --option 7 \
																						  			 --sample_name '$(SAMPLE_PAIRS)'")

hr_detect/signatures_summary.txt : $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).snv.fix.vcf.bgz) \
								   $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).snv.fix.vcf.bgz.tbi) \
								   $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).indel.fix.vcf.bgz) \
								   $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).indel.fix.vcf.bgz.tbi) \
								   $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).sv.bedpe) \
								   $(foreach pair,$(SAMPLE_PAIRS),hr_detect/$(pair)/$(pair).cn.txt)
	$(call RUN, -c -n 4 -s 6G -m 9G -v $(SIGNATURE_TOOLS_ENV) -p $(PROJECT_DIR)/summary -N signatures,"set -o pipefail && \
																						  			   $(RSCRIPT) $(SCRIPTS_DIR)/signature_tools/hr_detect.R \
																						  			   --option 8 \
																						  			   --sample_name '$(SAMPLE_PAIRS)'")
		
..DUMMY := $(shell mkdir -p version; \
	$(SIGNATURE_TOOLS_ENV)/bin/R --version &> version/hr_detect.txt;)
.SECONDARY:
.DELETE_ON_ERROR:
.PHONY: clean

clean :
	rm -f hr_detect/*_*/*_*.snv.vcf) && \
	rm -f hr_detect/*_*/*_*.snv.vcf.bgz) && \
	rm -f hr_detect/*_*/*_*.snv.vcf.bgz.tbi) && \
	rm -f hr_detect/*_*/*_*.snv.fix.vcf) && \
	rm -f hr_detect/*_*/*_*.snv.fix.vcf.bgz) && \
	rm -f hr_detect/*_*/*_*.snv.fix.vcf.bgz.tbi) && \
	rm -f hr_detect/*_*/*_*.indel.vcf) && \
	rm -f hr_detect/*_*/*_*.indel.vcf.bgz) && \
	rm -f hr_detect/*_*/*_*.indel.vcf.bgz.tbi) && \
	rm -f hr_detect/*_*/*_*.indel.fix.vcf) && \
	rm -f hr_detect/*_*/*_*.indel.fix.vcf.bgz) && \
	rm -f hr_detect/*_*/*_*.indel.fix.vcf.bgz.tbi) && \
	rm -f hr_detect/*_*/*_*.merged.bed) && \
	rm -f hr_detect/*_*/*_*.merged.bedpe) && \
	rm -f hr_detect/*_*/*_*.sv.bedpe) && \
	rm -f hr_detect/*_*/*_*.cn.txt)