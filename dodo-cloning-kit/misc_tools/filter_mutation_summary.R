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

optList <- list(make_option("--input", default = 'mutation_summary/mutation_summary.txt', help = "input file"),
				make_option("--filter", default = 'weigelt-lab/rda_cache/rpart.im.obj', help = "rpart classification tree"),
				make_option("--output", default = 'mutation_summary/mutation_summary_ft.txt', help = "output file"))

parser <- OptionParser(usage = "%prog vcf.files", option_list = optList)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

mutation_smry = readr::read_tsv(file = as.character(opt$input), col_names = TRUE, col_types = cols(.default = col_character())) %>%
			    readr::type_convert()

#––––––––––––––––––––––––––––––––––––––––––––––––––
# 1. Filter MAF from iris by replicating variant
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
						   
				# filter out unwanted variant caller combination
				
				dplyr::mutate(`Is_filtered?` = case_when(
									`Is_mutect?` == "yes" ~ TRUE,
									(nchar(Reference_Allele)==1 & nchar(Tumor_Seq_Allele2)==1) & `Is_varscan?` == "yes" ~ TRUE,
									(nchar(Reference_Allele)>1 | nchar(Tumor_Seq_Allele2)>1) & `Is_varscan?` == "yes" & (`Is_scalpel?` == "yes" | `Is_strelka?` == "yes") ~ TRUE,
									(nchar(Reference_Allele)>1 | nchar(Tumor_Seq_Allele2)>1) & `Is_scalpel?` == "yes" & `Is_strelka?` == "yes" ~ TRUE,
									TRUE ~ FALSE
				)) %>%
				dplyr::filter(`Is_filtered?`) %>%
				dplyr::select(-`Is_filtered?`) %>%
				
				
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
# 2. Get a table of all positives (TP + FP)
#––––––––––––––––––––––––––––––––––––––––––––––––––
mutation_smry = mutation_smry %>%
			    dplyr::mutate(Reference_Allele_L = nchar(Reference_Allele)) %>%
			    dplyr::mutate(Tumor_Seq_Allele2_L = nchar(Tumor_Seq_Allele2)) %>%
			    dplyr::mutate(Variant_Length = case_when(
		   			Reference_Allele_L > Tumor_Seq_Allele2_L ~ Reference_Allele_L,
		   			TRUE ~ Tumor_Seq_Allele2_L
			    )) %>%
			    dplyr::mutate(n_maf = n_alt_count/n_depth,
		   				      t_maf = t_alt_count/t_depth,
		   				      `t/n maf` = t_maf/(n_maf+1e-9)) %>%
			    dplyr::select(
			   				  # annotations to use as variables

			   				  Variant_Type, Variant_Length,
			   				  n_alt_count,
			   				  ExAC_AF,
			   				  ExAC_AF_Adj,
			   				  gnomAD_AF,
			   				  FILTER,
			   				  ExAC_FILTER,
			   				  `Is_mutect?`, `Is_varscan?`, `Is_strelka?`, `Is_scalpel?`, `Is_platypus?`,
			   				  Is_cmo_hotspot, Is_cancer_hotspot) %>%
			    dplyr::mutate(Variant_Type = case_when(
		   						   Variant_Type == "INS" | Variant_Type == "DEL" ~ "INDEL",
		   						   TRUE ~ "SNP"),
		   				      ExAC_AF = ifelse(is.na(ExAC_AF), 0, ExAC_AF),
						      ExAC_AF_Adj = ifelse(is.na(ExAC_AF_Adj), 0, ExAC_AF_Adj),
						      gnomAD_AF = ifelse(is.na(gnomAD_AF), 0, gnomAD_AF),
						      ExAC_FILTER = case_when(
						 		   is.na(ExAC_FILTER) ~ "UNKNOWN",
						 		   grepl("VQSRTranche", ExAC_FILTER) ~ "FAIL",
						 		   grepl("InbreedingCoeff", ExAC_FILTER) ~ "FAIL",
						 		   TRUE ~ ExAC_FILTER)) %>%
		       readr::type_convert()

#––––––––––––––––––––––––––––––––––––––––––––––––––
# 6. Decision tree. Use parameter set that overfits
#    and plot decision tree and ROC curve
#––––––––––––––––––––––––––––––––––––––––––––––––––
load(as.character(opt$filter))
prd = predict(object = fit, newdata = mutation_smry, type = "prob")
all_coords = pROC::roc(response = validation$`Is_lilac?`, predictor = prd[,"Lilac (+)"], ret = "all_coords")
