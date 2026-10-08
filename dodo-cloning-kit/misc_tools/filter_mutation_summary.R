#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("optparse"))
suppressPackageStartupMessages(library('dplyr'))
suppressPackageStartupMessages(library('readr'))
suppressPackageStartupMessages(library('magrittr'))
suppressPackageStartupMessages(library('tidyr'))
suppressPackageStartupMessages(library('pander'))
suppressPackageStartupMessages(library("MASS"))
suppressPackageStartupMessages(library("rpart"))
suppressPackageStartupMessages(library("rpart.plot"))
suppressPackageStartupMessages(library("partykit"))

if (!interactive()) {
    options(warn = -1, error = quote({ traceback(); q('no', status = 1) }))
}

optList <- list(make_option("--input", default = 'summary/mutation_summary.txt', help = "input file"),
				make_option("--filter", default = 'weigelt-lab/rda_cache/rpart.im.obj', help = "rpart classification tree"),
				make_option("--output", default = 'summary/mutation_summary_ft.txt', help = "output file"))

parser <- OptionParser(usage = "%prog vcf.files", option_list = optList)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

mutation_smry = readr::read_tsv(file = as.character(opt$input), col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert()

#––––––––––––––––––––––––––––––––––––––––––––––––––
# 1. Filter MAF by replicating variant
#    caller and variant class filters
#––––––––––––––––––––––––––––––––––––––––––––––––––
mutation_smry = mutation_smry %>%

				# filter out unwanted variant classes
				
				dplyr::filter(Variant_Classification != "In_Frame_Ins") %>%
				dplyr::filter(Variant_Classification != "In_Frame_Del") %>%
				dplyr::filter(Variant_Classification != "Splice_Region") %>%
				dplyr::filter(Variant_Classification != "Translation_Start_Site") %>%
				dplyr::filter(Variant_Classification != "3'Flank") %>%
				dplyr::filter(Variant_Classification != "3'UTR") %>%
				dplyr::filter(Variant_Classification != "5'Flank") %>%
				dplyr::filter(Variant_Classification != "5'UTR") %>%
				dplyr::filter(Variant_Classification != "IGR") %>%
				dplyr::filter(Variant_Classification != "Intron") %>%
				dplyr::filter(Variant_Classification != "RNA") %>%
				dplyr::filter(Variant_Classification != "Silent") %>%
				
				# filter out duplicate entries if any –– sanity
				
				dplyr::filter(!duplicated(paste0(Tumor_Sample_Barcode, Matched_Norm_Sample_Barcode, Chromosome, Start_Position, Reference_Allele, Tumor_Seq_Allele2))) %>%
						   
				# ADD MORE FILTERS HERE IF NECESSARY
				dplyr::filter(Chromosome != "MT") %>%
				dplyr::filter(Chromosome != "Y") %>%
				dplyr::filter(!grepl("^HLA", Hugo_Symbol, perl = TRUE)) %>%
				dplyr::filter(!grepl("^TTN", Hugo_Symbol, perl = TRUE)) %>%
				dplyr::filter(!grepl("^HIST", Hugo_Symbol, perl = TRUE)) %>%
				dplyr::filter(!grepl("^MUC", Hugo_Symbol, perl = TRUE)) %>%
				
				# remove platypus only variant calls
				dplyr::filter(!(`Is_platypus?` == "yes" & (`Is_mutect?` == "no" & `Is_varscan?` == "no" & `Is_strelka?` == "no" & `Is_scalpel?` == "no")))
				
#––––––––––––––––––––––––––––––––––––––––––––––––––
# 2. Get a table of all positives
#––––––––––––––––––––––––––––––––––––––––––––––––––
df_to_filter = mutation_smry %>%
			   dplyr::select(Variant_Type,
			   				 n_alt_count,
			   				 ExAC_AF,
			   				 gnomAD_AF,
			   				 FILTER,
			   				 ExAC_FILTER,
			   				 `Is_mutect?`, `Is_varscan?`, `Is_strelka?`, `Is_scalpel?`, `Is_platypus?`,
			   				 Is_cmo_hotspot, Is_cancer_hotspot) %>%
			   dplyr::mutate(Variant_Type = case_when(
		   						   Variant_Type == "INS" | Variant_Type == "DEL" ~ "INDEL",
		   						   TRUE ~ "SNP"),
		   				     ExAC_AF = ifelse(is.na(ExAC_AF), 0, ExAC_AF),
						     gnomAD_AF = ifelse(is.na(gnomAD_AF), 0, gnomAD_AF),
						     ExAC_FILTER = case_when(
						 		   is.na(ExAC_FILTER) ~ "UNKNOWN",
						 		   grepl("VQSRTranche|InbreedingCoeff|AC_Adj0_Filter", ExAC_FILTER, fixed = FALSE, perl = TRUE) ~ "FAIL",
						 		   TRUE ~ ExAC_FILTER)) %>%
		      readr::type_convert()

#––––––––––––––––––––––––––––––––––––––––––––––––––
# 3. Classify variants using decision tree
#––––––––––––––––––––––––––––––––––––––––––––––––––
load(as.character(opt$filter))
cl = predict(object = fit, newdata = df_to_filter, type = "class")
pr = predict(object = fit, newdata = df_to_filter, type = "prob")
df = dplyr::tibble(`Is_FP?` = cl,
				   `Pr_FP`  = pr[,1]) %>%
	 dplyr::mutate(`Is_FP?` = case_when(
	 					`Is_FP?` == "Lilac (+)" ~ "No",
	 					`Is_FP?` == "Lilac (-)" ~ "Yes"
	 ))

#––––––––––––––––––––––––––––––––––––––––––––––––––
# 4. Write output
#––––––––––––––––––––––––––––––––––––––––––––––––––
mutation_smry %>%
dplyr::bind_cols(df) %>%
readr::write_tsv(file = as.character(opt$output), append = FALSE, col_names = TRUE)

