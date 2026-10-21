#!/usr/bin/env Rscript

# DLP single-cell copy number analysis
#   --option 1   QC metrics + QC plots
#   --option 2   Log2 Ratio plot per cell
#   --option 3   Ploidy (RMSE) fit per cell
#   --option 4   Absolute copy number per cell
#   --option 5   Heatmap of absolute copies
#   --option 6   Absolute copies, all bins
#   --option 7   Marginal CN distribution/gene
#   --option 8   Clonal decomposition
#
# Tunable parameters
#   QC gates          --min_total_reads --max_mapd --min_log2_ratio --fraction_empty_bins --min_ploidy
#   Control names     --control_pattern --cell_control_pattern --negative_control_pattern
#   Ploidy search     --rmse_ploidy --rmse_penalty --rmse_step
#   Segmentation      --winsorize_tau --winsorize_k --pcf_gamma --mpcf_gamma
#   Display           --max_copies
#   Clones            --clone_height --clone_linkage
#
# Dependencies
#   1 -> 2
#   1 -> 3 -> 4, 5, 6 -> 7, 8

suppressPackageStartupMessages({
	library("optparse")
	library("ggplot2")
	library("readr")
	library("dplyr")
	library("tidyr")
	library("reshape2")
	library("magrittr")
	library("purrr")
	library("scales")
	library("RColorBrewer")
	library("foreach")
	library("doMC")
	library("fuzzyjoin")
	library("GenomicRanges")
	library("copynumber")
	library("ComplexHeatmap")
})

args_list <- list(
	make_option("--option", type = "integer", default = NA,
				help = "Analysis step to run (see header of this script)"),
	make_option("--summary_dir", type = "character", default = "summary",
				help = "Directory with input files [default: %default]"),
	make_option("--output_dir", type = "character", default = "DLP",
				help = "Directory for output files [default: %default]"),
	make_option("--sample_names", type = "character", default = NULL,
				help = "Space-separated cell names e.g. '$(SAMPLES)'"),
	make_option("--gene_coords", type = "character", default = "~/share/lib/bed_files/targets/IMPACT505/b37/gene_coords.txt",
				help = "Path to gene coordinates table"),
	make_option("--genes", type = "character", default = "MYC,CCNE1,MAPK3,CEBPA,KMT2B",
				help = "Comma-separated genes to plot [default: %default]"),
	make_option("--ncores", type = "integer", default = 12,
				help = "Number of cores for per-cell loops [default: %default]"),

	make_option("--min_total_reads", type = "double", default = 2.5e5,
				help = "Minimum number of aligned read pairs [default: %default]"),
	make_option("--max_mapd", type = "double", default = 0.5,
				help = "Maximum MAPD [default: %default]"),
	make_option("--min_log2_ratio", type = "double", default = -2,
				help = "Bins with log2 ratio below this value are counted as empty [default: %default]"),
	make_option("--fraction_empty_bins", type = "double", default = 0.0625,
				help = "Maximum fraction of empty bins on any chromosome [default: %default]"),
	make_option("--min_ploidy", type = "double", default = 1.75,
				help = "Minimum estimated ploidy [default: %default]"),

	make_option("--control_pattern", type = "character", default = "CONTROL",
				help = "Regular expression identifying DLP control cells [default: %default]"),
	make_option("--cell_control_pattern", type = "character", default = "DLPcellCONTROL",
				help = "Regular expression identifying positive cell controls [default: %default]"),
	make_option("--negative_control_pattern", type = "character", default = "DLPNegativeCONTROL",
				help = "Regular expression identifying negative cell controls [default: %default]"),

	make_option("--rmse_ploidy", type = "character", default = "1.5,6",
				help = "Comma-separated lower and upper ploidy searched [default: %default]"),
	make_option("--rmse_penalty", type = "double", default = 0,
				help = "Ploidy penalty added to the RMSE (score = rmse + (penalty * ploidy)) [default: %default]"),
	make_option("--rmse_step", type = "double", default = 0.01,
				help = "Step size of the ploidy search [default: %default]"),

	make_option("--winsorize_tau", type = "double", default = .5,
				help = "copynumber::winsorize tau [default: %default]"),
	make_option("--winsorize_k", type = "integer", default = 15,
				help = "copynumber::winsorize k [default: %default]"),
	make_option("--pcf_gamma", type = "double", default = 10,
				help = "copynumber::pcf gamma, single-cell segmentation [default: %default]"),
	make_option("--mpcf_gamma", type = "double", default = 1,
				help = "copynumber::multipcf gamma, joint segmentation of all cells (option 8) [default: %default]"),

	make_option("--max_copies", type = "integer", default = 10,
				help = "Copy number is capped at this value in the heatmaps [default: %default]"),

	make_option("--clone_height", type = "double", default = 0.2,
				help = "Height at which the cell dendrogram is cut into clones [default: %default]"),
	make_option("--clone_linkage", type = "character", default = "complete",
				help = "hclust linkage used for the clone dendrogram [default: %default]")
)
parser <- OptionParser(usage = "%prog", option_list = args_list)
arguments <- parse_args(parser, positional_arguments = T)
opt <- arguments$options

if (is.na(opt$option) || !(opt$option %in% 1:8)) {
	stop("--option must be an integer between 1 and 8", call. = FALSE)
}

numeric_args = c(
  "min_total_reads",
  "max_mapd",
  "min_log2_ratio",
  "fraction_empty_bins",
  "min_ploidy",
  "rmse_penalty",
  "rmse_step",
  "winsorize_tau",
  "winsorize_k",
  "pcf_gamma",
  "mpcf_gamma",
  "max_copies",
  "clone_height"
)
for (arg in numeric_args) {
	if (!is.numeric(opt[[arg]]) || length(opt[[arg]]) != 1 || is.na(opt[[arg]])) {
		stop("--", arg, " must be a single number", call. = FALSE)
	}
}

ploidy_bounds = as.numeric(strsplit(opt$rmse_ploidy, ",")[[1]])
if (length(ploidy_bounds) != 2 || any(is.na(ploidy_bounds)) || ploidy_bounds[1] >= ploidy_bounds[2]) {
	stop("--rmse_ploidy must be two increasing numbers separated by a comma, e.g. 1.5,6", call. = FALSE)
}
if (opt$rmse_step <= 0) {
	stop("--rmse_step must be positive", call. = FALSE)
}
if (opt$max_copies < 1 || opt$max_copies > 10) {
	stop("--max_copies must be between 1 and 10", call. = FALSE)
}
if (!(opt$clone_linkage %in% c("ward.D", "ward.D2", "single", "complete", "average", "mcquitty", "median", "centroid"))) {
	stop("--clone_linkage must be a valid hclust method", call. = FALSE)
}

if (opt$ncores > 1) {
	registerDoMC(opt$ncores)
} else {
	registerDoSEQ()
}

chromosomes = c(1:22, "X")
cn_colors = c("0" = "#a6cee3",
			  "1" = "#1f78b4",
			  "2" = "#b2df8a",
			  "3" = "#33a02c",
			  "4" = "#fb9a99",
			  "5" = "#e31a1c",
			  "6" = "#fdbf6f",
			  "7" = "#ff7f00",
			  "8" = "#cab2d6",
			  "9" = "#6a3d9a",
			  "10" = "#ffff99")

'url_summary' <- function(file) {
	file.path(opt$summary_dir, file)
}

'url_output' <- function(...) {
	file.path(opt$output_dir, ...)
}

'make_dir' <- function(...) {
	dir = url_output(...)
	if (!dir.exists(dir)) {
		dir.create(dir, recursive = TRUE)
	}
	return(invisible(dir))
}

'scientific_10' <- function(x) {
	parse(text = gsub("+", "", gsub("e", " %.% 10^", scales::scientific_format()(x)), fixed = TRUE))
}

'median_absolute_pairwise_deviation' <- function(
	data,
	chr_col = "chromosome",
	start_col = "start",
	end_col = "end",
	samples = NULL
) {

	needed = c(chr_col, start_col, end_col)
	if (!all(needed %in% colnames(data))) {
		stop("Missing column(s): ", paste(setdiff(needed, colnames(data)), collapse = ", "))
	}

	if (is.null(samples)) {
		candidates = setdiff(colnames(data), needed)
		samples = candidates[vapply(data[candidates], is.numeric, logical(1))]
	}
	if (length(samples) == 0) {
		stop("No numeric sample columns found.")
	}

	data = data[order(data[[chr_col]], data[[start_col]], data[[end_col]]), ]
	chr = as.character(data[[chr_col]])

	mapd_one <- function(s) {
		x = data[[s]]
		keep = !is.na(x)
		x = x[keep]
		ch = chr[keep]
		if (length(x) < 2) {
			return(NA_real_)
		}
		d = abs(diff(x))
		d = d[ch[-1] == ch[-length(ch)]]
		if (length(d) == 0) {
			res = NA_real_
		} else {
			res = median(d)
		}
		return(res)
	}

	res = vapply(samples, mapd_one, numeric(1))
	res = dplyr::tibble(barcode_id = samples,
						MAPD = unname(res))

	return(invisible(res))
}

'estimate_ploidy' <- function(
	segments,
	ploidy_range,
	penalty,
	step
) {

	seg = segments %>%
		dplyr::mutate(width = End_Position - Start_Position + 1) %>%
		dplyr::filter(is.finite(Log2_Ratio), width > 0)

	ploidies = seq(ploidy_range[1], ploidy_range[2], by = step)

	fit = lapply(ploidies, function(p) {
		cn_raw = p * 2^seg$Log2_Ratio
		cn_int = pmax(round(cn_raw), 0)
		rmse   = sqrt(weighted.mean((cn_raw - cn_int)^2, w = seg$width))
		data.frame(ploidy = p, rmse = rmse, score = rmse + penalty * p)
	}) %>% dplyr::bind_rows()

	best = fit[which.min(fit$score), ]

	s = fit$score
	idx = which(diff(sign(diff(s))) == 2) + 1
	local_min = fit[idx, ] %>% dplyr::arrange(score)

	seg_cn = seg %>%
		dplyr::mutate(CN_raw = best$ploidy * 2^Log2_Ratio,
					  CN     = pmax(round(CN_raw), 0))

	mean_cn = weighted.mean(seg_cn$CN, seg_cn$width)

	res = list(ploidy      = best$ploidy,
			   mean_cn     = mean_cn,
			   fit         = fit,
			   local_min   = local_min,
			   best        = best,
			   segments_cn = seg_cn)

	return(invisible(res))
}

'read_tsv_typed' <- function(
	file,
	col_names = TRUE
) {
	if (!file.exists(file)) {
		stop("Input file not found: ", file, call. = FALSE)
	}
	data = readr::read_tsv(file = file, col_names = col_names, col_types = cols(.default = col_character())) %>%
		   readr::type_convert()

	return(invisible(data))
}

'read_log2' <- function(midpoint = TRUE) {
	log2_ratio = read_tsv_typed(url_summary("aggregated_log2.txt"))
	if (midpoint) {
		log2_ratio = log2_ratio %>%
			dplyr::mutate(start = round(.5*(start+end))) %>%
			dplyr::rename(position = start) %>%
			dplyr::select(-end)
	}

	return(invisible(log2_ratio))
}

'qc_filter' <- function(
	manifest,
	ploidy = FALSE
) {
	fail = manifest$`is_dlp_control_yes_no?` == "yes" |
		   manifest$total_aligned_read_pairs < opt$min_total_reads |
		   manifest$median_absolute_pairwise_deviation > opt$max_mapd |
		   manifest$`any_missing_chromosome_yes_no?` == "yes"
	if (ploidy) {
		fail = fail | manifest$best_ploidy_estimate < opt$min_ploidy
	}
	res = manifest %>%
		  dplyr::mutate(QC_PASS = ifelse(fail %in% TRUE, "no", "yes")) %>%
		  dplyr::filter(QC_PASS == "yes")

	return(invisible(res))
}

'load_manifest' <- function(ploidy = FALSE) {
	file = ifelse(ploidy, "manifest_w_qc_ext.txt", "manifest_w_qc.txt")
	res = read_tsv_typed(url_output("qc", file)) %>%
		  qc_filter(ploidy = ploidy)

	return(invisible(res))
}

'segment_cell' <- function(
	log2_ratio,
	barcode_id,
	tau = opt$winsorize_tau,
	k = opt$winsorize_k,
	gamma = opt$pcf_gamma
) {

	log2_smoothed = log2_ratio %>%
					dplyr::select(all_of(c("chromosome", "position", barcode_id))) %>%
					dplyr::rename("Log2" = 3) %>%
					as.data.frame() %>%
					copynumber::winsorize(method = "mad", tau = tau, k = k, verbose = FALSE) %>%
					dplyr::rename(Chromosome = chrom, Position = pos)

	segmented_log2 = log2_smoothed %>%
					 copynumber::pcf(gamma = gamma, normalize = FALSE, fast = TRUE, verbose = FALSE) %>%
					 dplyr::select(-arm, -n.probes) %>%
					 dplyr::rename(Chromosome = chrom, Start_Position = start.pos, End_Position = end.pos) %>%
					 dplyr::mutate(Chromosome = case_when(
					 					Chromosome == 23 ~ "X",
					 					TRUE ~ as.character(Chromosome)
					 )) %>%
					 dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE)) %>%
					 dplyr::rename(sample_name = sampleID, Log2_Ratio = mean)

	res = list(smoothed = log2_smoothed, segments = segmented_log2)

	return(invisible(res))
}

'call_copy_number' <- function(
	segments,
	ploidy
) {
	res = segments %>%
		  dplyr::mutate(CN_raw = ploidy * 2^Log2_Ratio,
					    CN = pmax(round(CN_raw), 0))

	return(invisible(res))
}

'bin_copy_number' <- function(
	log2_smoothed,
	fit
) {
	res = log2_smoothed %>%
		  dplyr::mutate(Start_Position = Position, End_Position = Position) %>%
		  fuzzyjoin::genome_left_join(fit %>%
									  dplyr::select(Chromosome, Start_Position, End_Position, CN),
									  by = c("Chromosome", "Start_Position", "End_Position")) %>%
		  dplyr::select(Chromosome = Chromosome.x,
					    Position,
					    Log2,
					    CN)
					    
	return(invisible(res))
}

'bind_cells' <- function(
	res,
	barcode_ids,
	by
) {
	names(res) = barcode_ids
	res = res %>%
		  purrr::imap(~ {
			names(.x)[names(.x) == "CN"] <- .y
			as.data.frame(.x)
		  }) %>%
		  purrr::reduce(full_join, by = by)
	
	return(invisible(res))
}

'empty_bin_fraction' <- function(log2_ratio) {
	res = log2_ratio %>%
		  reshape2::melt(id.vars = c("chromosome", "start", "end"),
					     variable.name = "SAMPLE_NAME",
					     value.name = "log2") %>%
		  dplyr::group_by(chromosome, SAMPLE_NAME) %>%
		  dplyr::summarize(n = sum(log2<(opt$min_log2_ratio), na.rm = TRUE),
						   f = sum(log2<(opt$min_log2_ratio), na.rm = TRUE)/length(log2),
						   .groups = "drop")
						   
	return(invisible(res))
}

'control_key' <- function(data) {
	res = data %>%
		  dplyr::mutate(key = case_when(
							`is_dlp_control_yes_no?` == "no" ~ "Tumor",
							`is_cell_control_yes_no?` == "yes" ~ "+Ctrl",
							`is_negative_control_yes_no?` == "yes" ~ "-Ctrl"
		  )) %>%
		  dplyr::mutate(key = factor(key, levels = c("Tumor", "+Ctrl", "-Ctrl"), ordered = TRUE))
		  
	return(invisible(res))
}

'control_scales' <- function(alpha = c(1, .55, .55)) {
	res = list(
			scale_fill_manual(values = c("Tumor" = "#f7f7f7", "+Ctrl" = "#ca0020", "-Ctrl" = "#0571b0")),
			scale_color_manual(values = c("Tumor" = "#636363", "+Ctrl" = "#636363", "-Ctrl" = "#636363")),
			scale_alpha_manual(values = c("Tumor" = alpha[1], "+Ctrl" = alpha[2], "-Ctrl" = alpha[3])),
			guides(fill = guide_legend(title = ""),
				   color = guide_legend(title = ""),
				   alpha = guide_legend(title = ""))
		  )
		  
	return(invisible(res))
}

'qc_theme' <- function(x_text = TRUE) {
	th = theme(axis.title.x = element_text(margin = margin(t = 20), size = 16),
			   axis.title.y = element_text(margin = margin(r = 20), size = 16),
			   axis.text.y = element_text(size = 12),
			   panel.spacing = unit(2, "lines"))
	if (x_text) {
		th = th + theme(axis.text.x = element_text(size = 12))
	}
	res = list(theme_minimal(), th)
	
	return(invisible(res))
}

'save_pdf' <- function(
	plot,
	file,
	width,
	height
) {
	pdf(file = file, width = width, height = height)
	print(plot)
	dev.off()
	
	return(invisible(file))
}

'segment_layers' <- function(segmented_log2) {
	res = list(
		geom_segment(data = segmented_log2,
					 mapping = aes(x = Start_Position, y = Log2_Ratio, xend = End_Position, yend = Log2_Ratio),
					 color = "#e41a1c", inherit.aes = FALSE, linewidth = 1, lineend = "round"),
		geom_line(data = segmented_log2 %>%
						 tidyr::pivot_longer(c(Start_Position, End_Position)),
				  mapping = aes(x = value, y = Log2_Ratio),
				  color = "#e41a1c", inherit.aes = FALSE, linewidth = .1, lineend = "round")
	)
	
	return(invisible(res))
}

'log2_axes' <- function(legend_bottom = FALSE) {
	th = theme(axis.text.x = element_blank(),
			   axis.ticks.x = element_blank(),
			   axis.text.y = element_text(size = 8),
			   axis.title.y = element_text(size = 9, margin = margin(r = 10)),
			   axis.line.x = element_line(color = "black", linewidth = 0.5, lineend = "butt"),
			   strip.text.x = element_text(size = 5),
			   strip.text.y = element_blank(),
			   strip.background.x = element_blank(),
			   strip.placement = "outside",
			   panel.spacing.x = unit(0.2, "lines"),
			   panel.spacing.y = unit(2, "lines"),
			   panel.border = element_blank(),
			   plot.margin = unit(c(1.25, 1, 1.25, 1), "cm"))
	if (legend_bottom) {
		th = th + theme(legend.position = "bottom")
	}
	res = list(
			geom_hline(yintercept = 0, color = "#d95f02", linetype = 2, linewidth = .5),
			geom_hline(yintercept = log2(c(1, 3, 4, 8, 12)/2), color = "#1b9e77", linetype = 2, linewidth = .25),
			xlab("\n\n"),
			ylab(expression(Log[2]~"Ratio")),
			scale_x_continuous(labels = scientific_10),
			scale_y_continuous(expand = c(0, 0),
							   breaks = c(-6, -4, -2, 0, 2, 4, 6),
							   labels = c(-6, -4, -2, 0, 2, 4, 6),
							   limits = c(-4, 6)),
			theme_classic(),
			th,
			facet_grid(~Chromosome, scales = "free_x", space = "free_x", switch = "x")
		)
		
	return(invisible(res))
}


# Option 1: QC metrics ———————————————————————————————————————————————————————————————————
'run_qc' <- function() {

	if (is.null(opt$sample_names)) {
		stop("--sample_names is required for --option 1", call. = FALSE)
	}
	sample_names = strsplit(trimws(opt$sample_names), "[[:space:]]+")[[1]]

	manifest = dplyr::tibble(barcode_id = sample_names) %>%
			   dplyr::mutate(`is_dlp_control_yes_no?` = ifelse(grepl(opt$control_pattern, barcode_id), "yes", "no")) %>%
			   dplyr::mutate(`is_cell_control_yes_no?` = ifelse(grepl(opt$cell_control_pattern, barcode_id), "yes", "no")) %>%
			   dplyr::mutate(`is_negative_control_yes_no?` = ifelse(grepl(opt$negative_control_pattern, barcode_id), "yes", "no")) %>%
			   dplyr::rename(SAMPLE_NAME = barcode_id)

	aln_metrics = read_tsv_typed(url_summary("aln_metrics.txt")) %>%
				  dplyr::filter(CATEGORY == "PAIR") %>%
				  dplyr::mutate(TOTAL_READS = round(TOTAL_READS/2))
	idx_metrics = read_tsv_typed(url_summary("idx_metrics.txt"))
	log2_ratio = read_log2(midpoint = FALSE)

	mapd = log2_ratio %>%
		   median_absolute_pairwise_deviation() %>%
		   dplyr::rename(SAMPLE_NAME = barcode_id)
	ebf = empty_bin_fraction(log2_ratio)

	make_dir("DLP/QC")

	# 1. Histogram of total read pairs aligned ———————————————————————————————————————————
	plot_ = manifest %>%
			dplyr::full_join(aln_metrics, by = "SAMPLE_NAME") %>%
			control_key() %>%
			ggplot(aes(x = TOTAL_READS, color = key, fill = key, alpha = key)) +
			geom_histogram(stat = "bin", position = "identity") +
			geom_vline(xintercept = opt$min_total_reads, color = "goldenrod3", linetype = 2) +
			control_scales(alpha = c(1, .55, .55)) +
			scale_x_continuous(labels = scientific_10) +
			scale_y_continuous() +
			xlab("\nAligned Read Pairs") +
			ylab("Frequency\n") +
			qc_theme(x_text = TRUE)
	save_pdf(plot_, url_output("QC", "aligned_read_pairs.pdf"), width = 5, height = 5)

	# 2. Histogram of MAPD ———————————————————————————————————————————————————————————————
	plot_ = manifest %>%
			dplyr::full_join(mapd, by = "SAMPLE_NAME") %>%
			control_key() %>%
			ggplot(aes(x = MAPD, color = key, fill = key, alpha = key)) +
			geom_histogram(stat = "bin", position = "identity") +
			geom_vline(xintercept = opt$max_mapd, color = "goldenrod3", linetype = 2) +
			control_scales(alpha = c(1, .55, .55)) +
			scale_x_continuous() +
			scale_y_continuous() +
			xlab("\nMAPD") +
			ylab("Frequency\n") +
			qc_theme(x_text = TRUE)
	save_pdf(plot_, url_output("QC", "mapd.pdf"), width = 5, height = 5)

	# 3. Scatter plot of MAPD by total aligned read pairs ————————————————————————————————
	plot_ = manifest %>%
			dplyr::full_join(aln_metrics, by = "SAMPLE_NAME") %>%
			dplyr::full_join(mapd, by = "SAMPLE_NAME") %>%
			control_key() %>%
			ggplot(aes(x = MAPD, y = TOTAL_READS, color = key, fill = key, alpha = key)) +
			geom_point(position = "identity", shape = 21, size = 2) +
			geom_vline(xintercept = opt$max_mapd, color = "goldenrod3", linetype = 2) +
			geom_hline(yintercept = opt$min_total_reads, color = "goldenrod3", linetype = 2) +
			control_scales(alpha = c(.75, .75, .75)) +
			scale_x_continuous() +
			scale_y_continuous(labels = scientific_10) +
			xlab("\nMAPD") +
			ylab("Number of Aligned Read Pairs\n") +
			qc_theme(x_text = TRUE)
	save_pdf(plot_, url_output("QC", "mapd_by_aligned_read_pairs.pdf"), width = 6, height = 5)

	# 4. Histogram of fraction of empty bins by chromosome ———————————————————————————————
	plot_ = manifest %>%
			dplyr::full_join(ebf, by = "SAMPLE_NAME") %>%
			control_key() %>%
			dplyr::mutate(chromosome = factor(chromosome, levels = chromosomes, ordered = TRUE)) %>%
			ggplot(aes(x = f, color = key, fill = key, alpha = key)) +
			geom_histogram(stat = "bin", position = "identity") +
			control_scales(alpha = c(1, .55, .55)) +
			scale_x_continuous() +
			scale_y_continuous() +
			xlab("\n\nFraction of Empty Bins\n") +
			ylab("\nFrequency\n\n") +
			qc_theme(x_text = FALSE) +
			facet_wrap(~chromosome)
	save_pdf(plot_, url_output("QC", "empty_bins_by_chromosome.pdf"), width = 17, height = 14)

	# 5. Histogram of aligned read pairs by chromosome ———————————————————————————————————
	plot_ = manifest %>%
			dplyr::full_join(idx_metrics, by = "SAMPLE_NAME") %>%
			dplyr::filter(CHROMOSOME %in% chromosomes) %>%
			dplyr::mutate(CHROMOSOME = factor(CHROMOSOME, levels = chromosomes, ordered = TRUE)) %>%
			control_key() %>%
			ggplot(aes(x = 100000*ALIGNED_READS/LENGTH, color = key, fill = key, alpha = key)) +
			geom_histogram(stat = "bin", position = "identity") +
			control_scales(alpha = c(1, .55, .55)) +
			scale_x_continuous(labels = scientific_10) +
			scale_y_continuous() +
			xlab("\n\nNumber of Aligned Read Pairs / 100Kbp\n") +
			ylab("\nFrequency\n\n") +
			qc_theme(x_text = FALSE) +
			facet_wrap(~CHROMOSOME, scales = "free_x")
	save_pdf(plot_, url_output("QC", "aligned_read_pairs_by_chromosome.pdf"), width = 17, height = 14)

	# 6. Scatter plot of fraction of empty bins by aligned read pairs, per chromosome ————
	plot_ = manifest %>%
			dplyr::full_join(ebf %>%
							 dplyr::rename(CHROMOSOME = chromosome),
							 by = "SAMPLE_NAME") %>%
			dplyr::full_join(idx_metrics, by = c("SAMPLE_NAME", "CHROMOSOME")) %>%
			control_key() %>%
			dplyr::mutate(CHROMOSOME = factor(CHROMOSOME, levels = chromosomes, ordered = TRUE)) %>%
			tidyr::drop_na(CHROMOSOME) %>%
			ggplot(aes(x = 100000*ALIGNED_READS/LENGTH, y = f, color = key, fill = key, alpha = key)) +
			geom_point(stat = "identity", shape = 21) +
			control_scales(alpha = c(1, .55, .55)) +
			scale_x_log10(labels = scientific_10) +
			scale_y_continuous() +
			xlab("\n\nNumber of Aligned Read Pairs / 100Kbp\n") +
			ylab("\nFraction of Empty Bins\n\n") +
			qc_theme(x_text = FALSE) +
			facet_wrap(~CHROMOSOME, scales = "free_x")
	save_pdf(plot_, url_output("QC", "aligned_read_pairs_empty_bins_by_chromosome.pdf"), width = 17, height = 14)

	# 7. Summarize all QC metrics ————————————————————————————————————————————————————————
	manifest %>%
	dplyr::full_join(aln_metrics, by = "SAMPLE_NAME") %>%
	dplyr::full_join(mapd, by = "SAMPLE_NAME") %>%
	dplyr::full_join(ebf %>%
					 dplyr::group_by(SAMPLE_NAME) %>%
					 dplyr::summarize(ANY_MISSING = ifelse(any(f>opt$fraction_empty_bins), "yes", "no")) %>%
					 dplyr::ungroup(),
					 by = "SAMPLE_NAME") %>%
	dplyr::select(barcode_id = SAMPLE_NAME,
				  `is_dlp_control_yes_no?`,
				  `is_cell_control_yes_no?`,
				  `is_negative_control_yes_no?`,
				  total_aligned_read_pairs = TOTAL_READS,
				  median_absolute_pairwise_deviation = MAPD,
				  `any_missing_chromosome_yes_no?` = ANY_MISSING) %>%
	readr::write_tsv(file = url_output("QC", "manifest.txt"), append = FALSE, col_names = TRUE)
}

#==================================================
# Option 2: Log2 ratio plot per cell (was 02_plot_log2_ratio.R)
#==================================================
'run_log2_plots' <- function() {

	manifest = load_manifest(ploidy = FALSE)
	log2_ratio = read_log2()
	make_dir("bycell", "log2")

	res = foreach (i=1:nrow(manifest)) %dopar% {

		cell = segment_cell(log2_ratio, manifest$barcode_id[i])

		plot_ = cell$smoothed %>%
				dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE)) %>%
				ggplot(aes(x = Position, y = Log2)) +
				geom_point(stat = "identity", fill = NA, color = "#1b9e77", shape = 16, size = .55, alpha = 1) +
				segment_layers(cell$segments) +
				log2_axes(legend_bottom = FALSE) +
				guides(color = "none")

		save_pdf(plot_, url_output("bycell", "log2", paste0(manifest$barcode_id[i], ".pdf")),
				 width = 24/2.25, height = 3)
		return(invisible(0))
	}
}

#==================================================
# Option 3: Ploidy estimation per cell (was 03a_rmse_fit.R)
#==================================================
'run_ploidy' <- function() {

	manifest = load_manifest(ploidy = FALSE)
	log2_ratio = read_log2()
	make_dir("bycell", "rmse")

	rmse = foreach (i=1:nrow(manifest)) %dopar% {

		cell = segment_cell(log2_ratio, manifest$barcode_id[i])
		fit = estimate_ploidy(segments = cell$segments, ploidy_range = ploidy_bounds, penalty = opt$rmse_penalty, step = opt$rmse_step)

		plot_ = fit$fit %>%
				ggplot(aes(x = ploidy, y = score)) +
				geom_line(linewidth = 0.7) +
				geom_point(data = fit$local_min, colour = "steelblue", size = 2.5) +
				geom_point(data = fit$best, colour = "red", size = 4) +
				geom_vline(xintercept = fit$best$ploidy, linetype = "dashed", colour = "red") +
				scale_x_continuous(limits = ploidy_bounds) +
				scale_y_continuous(limits = c(0, .5)) +
				annotate("text", x = fit$best$ploidy, y = max(fit$fit$score),
						 label = sprintf("++ = %.2f", fit$best$ploidy),
						 hjust = -0.1, vjust = 1, colour = "red") +
				labs(x = "Ploidy",
					 y = "Weighted RMSE",
					 title = manifest$barcode_id[i],
					 subtitle = "Red = global minimum,\nblue = other local minima") +
				theme_minimal() +
				theme(plot.title = element_text(size = 9),
					  plot.subtitle = element_text(size = 5),
					  axis.title.x = element_text(margin = margin(t = 10), size = 10),
					  axis.title.y = element_text(margin = margin(r = 10), size = 10),
					  axis.text.x = element_text(size = 8),
					  axis.text.y = element_text(size = 8),
					  panel.spacing = unit(2, "lines"))

		save_pdf(plot_, url_output("bycell", "rmse", paste0(manifest$barcode_id[i], ".pdf")),
				 width = 3, height = 3)

		fit$best = fit$best %>%
				   dplyr::mutate("N" = nrow(fit$segments_cn))
		return(invisible(fit$best))
	}

	# Extend the (unfiltered) QC manifest with the ploidy fit of the cells that passed QC
	read_tsv_typed(url_output("qc", "manifest_w_qc.txt")) %>%
	dplyr::left_join(do.call(rbind, rmse) %>%
					 dplyr::mutate(barcode_id = manifest$barcode_id) %>%
					 dplyr::rename(best_ploidy_estimate = ploidy,
								   root_mean_square_error = rmse,
								   penalized_rmse = score,
								   number_of_segments = N),
					 by = "barcode_id") %>%
	readr::write_tsv(file = url_output("qc", "manifest_w_qc_ext.txt"), append = FALSE, col_names = TRUE)
}

#==================================================
# Option 4: Absolute copy number plot per cell (was 03b_plot_absolute_copies.R)
#==================================================
'run_absolute_plots' <- function() {

	manifest = load_manifest(ploidy = TRUE)
	log2_ratio = read_log2()
	make_dir("bycell", "absolute")

	res = foreach (i=1:nrow(manifest)) %dopar% {

		cell = segment_cell(log2_ratio, manifest$barcode_id[i])
		fit = call_copy_number(cell$segments, ploidy = manifest$best_ploidy_estimate[i])

		pal = colorRampPalette(brewer.pal(n = 8, "Dark2"))(length(unique(fit$CN)))
		names(pal) = as.character(sort(unique(fit$CN)))

		plot_ = bin_copy_number(cell$smoothed, fit) %>%
				dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE),
							  CN = factor(CN, levels = sort(unique(CN)), ordered = TRUE)) %>%
				ggplot(aes(x = Position, y = Log2, color = CN)) +
				geom_point(stat = "identity", fill = NA, shape = 16, size = .55, alpha = .35) +
				scale_color_manual(values = pal) +
				segment_layers(cell$segments) +
				log2_axes(legend_bottom = TRUE) +
				guides(color = guide_legend(title = "Copies", nrow = 1, override.aes = list(size = 2)))

		save_pdf(plot_, url_output("bycell", "absolute", paste0(manifest$barcode_id[i], ".pdf")),
				 width = 24/2.25, height = 3.25)
		return(invisible(0))
	}
}

#==================================================
# Option 5: Heatmap of absolute copy number (was 04_heatmap_absolute_copies.R)
#==================================================
'run_heatmap' <- function() {

	manifest = load_manifest(ploidy = TRUE)
	log2_ratio = read_log2()
	make_dir("smry")

	res = foreach (i=1:nrow(manifest)) %dopar% {

		cell = segment_cell(log2_ratio, manifest$barcode_id[i])
		fit = call_copy_number(cell$segments, ploidy = manifest$best_ploidy_estimate[i])

		bin_copy_number(cell$smoothed, fit) %>%
		dplyr::select(-Log2) %>%
		dplyr::as_tibble() %>%
		dplyr::mutate(CN = pmin(CN, opt$max_copies))
	}

	copy_number = bind_cells(res, manifest$barcode_id, by = c("Chromosome", "Position")) %>%
				  dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE),
								Position = as.numeric(Position)) %>%
				  dplyr::arrange(Chromosome, Position)

	pdf(url_output("smry", "aggregated_cells_absolute_copies.pdf"), width = 7*2.5, height = 7*1.25)
	draw(Heatmap(matrix = copy_number %>%
						  dplyr::select(-Chromosome, -Position) %>%
						  t(),
				 col = cn_colors[as.character(0:opt$max_copies)],
				 name = "CN",
				 na_col = "#f0f0f0",
				 rect_gp = gpar(col = NA, lwd = 0),
				 border = NA,

				 cluster_rows = TRUE,
				 clustering_distance_rows = "manhattan",
				 clustering_method_rows = "complete",
				 row_dend_width = unit(30, "mm"),
				 show_row_names = FALSE,

				 cluster_columns = FALSE,
				 column_split = copy_number %>% .[["Chromosome"]],
				 show_column_names = FALSE,
				 column_title_side = "bottom",
				 column_title_gp = gpar(fontsize = 12),

				 use_raster = FALSE,
				 show_heatmap_legend = TRUE,
				 heatmap_legend_param = list(legend_height = unit(1, "cm"), legend_width = unit(1, "cm"))))
	dev.off()
}

#==================================================
# Option 6: Absolute copy number tables (was 05a_summary_bygene_absolute_copies.R)
#==================================================
'run_bygene_tables' <- function() {

	if (is.null(opt$gene_coords)) {
		stop("--gene_coords is required for --option 6", call. = FALSE)
	}

	manifest = load_manifest(ploidy = TRUE)
	log2_ratio = read_log2()

	gene_coords = read_tsv_typed(opt$gene_coords, col_names = FALSE) %>%
				  dplyr::group_by(X2) %>%
				  dplyr::summarize(Chromosome = unique(X3),
								   Start_Position = min(X4),
								   End_Position = max(X5)) %>%
				  dplyr::rename(Hugo_Symbol = X2)

	make_dir("smry")
	make_dir("bygene")

	# Segmentation is done once per cell and used for both the all-bins and the by-gene table
	res = foreach (i=1:nrow(manifest)) %dopar% {

		cell = segment_cell(log2_ratio, manifest$barcode_id[i])
		fit = call_copy_number(cell$segments, ploidy = manifest$best_ploidy_estimate[i])

		bins = log2_ratio %>%
			   dplyr::select(Chromosome = chromosome, Start_Position = position) %>%
			   dplyr::mutate(End_Position = Start_Position) %>%
			   fuzzyjoin::genome_left_join(fit %>%
										   dplyr::select(Chromosome, Start_Position, End_Position, CN),
										   by = c("Chromosome", "Start_Position", "End_Position")) %>%
			   dplyr::select(Chromosome = Chromosome.x,
							 Position = Start_Position.x,
							 CN) %>%
			   dplyr::as_tibble()

		genes = gene_coords %>%
				fuzzyjoin::genome_left_join(fit %>%
											dplyr::select(Chromosome, Start_Position, End_Position, CN),
											by = c("Chromosome", "Start_Position", "End_Position")) %>%
				dplyr::select(Hugo_Symbol,
							  Chromosome = Chromosome.x,
							  Start_Position = Start_Position.x,
							  End_Position = End_Position.x,
							  CN) %>%
				dplyr::as_tibble()

		return(list(bins = bins, genes = genes))
	}

	# 1. All bins
	copy_number = bind_cells(lapply(res, `[[`, "bins"), manifest$barcode_id, by = c("Chromosome", "Position")) %>%
				  dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE),
								Position = as.numeric(Position)) %>%
				  dplyr::arrange(Chromosome, Position)
	readr::write_tsv(x = copy_number, file = url_output("smry", "aggregated_cells_absolute_copies_all_bins.txt"),
					 append = FALSE, col_names = TRUE)

	# 2. All genes
	copy_number = bind_cells(lapply(res, `[[`, "genes"), manifest$barcode_id,
							 by = c("Hugo_Symbol", "Chromosome", "Start_Position", "End_Position")) %>%
				  dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE),
								Start_Position = as.numeric(Start_Position),
								End_Position = as.numeric(End_Position)) %>%
				  dplyr::arrange(Chromosome, Start_Position, End_Position)
	readr::write_tsv(x = copy_number, file = url_output("bygene", "aggregated_cells_absolute_copies_by_gene.txt"),
					 append = FALSE, col_names = TRUE)
}

#==================================================
# Option 7: Marginal CN distribution by gene (was 05b_plot_marginal_copies_bygene.R)
#==================================================
'run_bygene_plots' <- function() {

	genes_of_interest = trimws(strsplit(opt$genes, ",")[[1]])

	copy_number = read_tsv_typed(url_output("bygene", "aggregated_cells_absolute_copies_by_gene.txt")) %>%
				  reshape2::melt(id.vars = c("Hugo_Symbol", "Chromosome", "Start_Position", "End_Position"),
								 variable.name = "barcode_id", value.name = "CN")

	for (gene in genes_of_interest) {

		data = copy_number %>%
			   dplyr::filter(Hugo_Symbol == gene)
		if (nrow(data) == 0) {
			warning("Gene not found in by-gene table, skipping: ", gene)
			next
		}

		plot_ = data %>%
				ggplot(aes(x = CN)) +
				geom_histogram(stat = "bin", position = "identity", fill = "steelblue", color = "steelblue", alpha = .25) +
				scale_x_continuous(breaks = function(x) { unique(round(pretty(x, n = 5))) }) +
				scale_y_continuous() +
				xlab("Copy number") +
				ylab("Number of cells") +
				labs(title = paste0(gene, "\n")) +
				theme_minimal() +
				theme(axis.title.x = element_text(margin = margin(t = 20), size = 14),
					  axis.title.y = element_text(margin = margin(r = 20), size = 14),
					  axis.text.x = element_text(size = 12),
					  axis.text.y = element_text(size = 12),
					  plot.title = element_text(hjust = .5, face = "italic"))

		save_pdf(plot_, url_output("bygene", paste0("marginal_distribution_cells_", gene, ".pdf")),
				 width = 3, height = 4)
	}
}

#==================================================
# Option 8: Clonal decomposition (was 06_clonal_decomposition.R)
#==================================================
'run_clones' <- function() {

	manifest = load_manifest(ploidy = TRUE)
	log2_ratio = read_log2()
	make_dir("byclone")

	# 1. Joint segmentation and absolute copy number ——————————————————————————————————————
	log2_smoothed = log2_ratio %>%
					dplyr::select(all_of(c("chromosome", "position", manifest$barcode_id))) %>%
					as.data.frame() %>%
					copynumber::winsorize(method = "mad", tau = opt$winsorize_tau, k = opt$winsorize_k, verbose = FALSE) %>%
					dplyr::rename(Chromosome = chrom, Position = pos)

	segmented_log2 = log2_smoothed %>%
					 copynumber::multipcf(gamma = opt$mpcf_gamma, normalize = FALSE, fast = FALSE, verbose = FALSE) %>%
					 dplyr::select(-arm, -n.probes) %>%
					 dplyr::rename(Chromosome = chrom, Start_Position = start.pos, End_Position = end.pos) %>%
					 dplyr::mutate(Chromosome = case_when(
					 					Chromosome == 23 ~ "X",
					 					TRUE ~ as.character(Chromosome)
					 )) %>%
					 dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE))

	fit = segmented_log2 %>%
		  reshape2::melt(id.vars = c("Chromosome", "Start_Position", "End_Position"), variable.name = "barcode_id", value.name = "Log2_Ratio") %>%
		  dplyr::left_join(manifest, by = "barcode_id") %>%
		  dplyr::mutate(CN_raw = best_ploidy_estimate * 2^Log2_Ratio,
						CN = pmax(round(CN_raw), 0)) %>%
		  reshape2::dcast(Chromosome + Start_Position + End_Position ~ barcode_id, value.var = "CN")

	# 2. Estimate number of clones ————————————————————————————————————————————————————————
	sample_cols = setdiff(names(fit), c("Chromosome", "Start_Position", "End_Position"))
	cn = as.data.frame(fit)[, sample_cols]
	w = (fit$End_Position - fit$Start_Position)/sum(fit$End_Position - fit$Start_Position)
	d = as.matrix(dist(t(cn*w), method = "manhattan"))
	hc = hclust(as.dist(d), method = opt$clone_linkage)
	h = seq(from = 0, to = 1, by = .05)
	nc = vapply(h, function(x) { length(unique(cutree(hc, h = x))) }, numeric(1))

	plot_ = dplyr::tibble(d = h,
						  nc = nc) %>%
			ggplot(aes(x = d, y = nc)) +
			geom_line(stat = "identity", color = "steelblue", linewidth = .5) +
			geom_point(stat = "identity", shape = 21, fill = NA, color = "steelblue", size = 2) +
			geom_vline(data = ~ dplyr::filter(.x, nc == 2) %>% dplyr::filter(d == min(d)),
					   aes(xintercept = d), linetype = 2, colour = "red") +
			geom_vline(xintercept = opt$clone_height, linetype = 3, color = "goldenrod3") +
			scale_x_continuous() +
			scale_y_continuous() +
			xlab("Weighted manhattan distance") +
			ylab("Number of clones") +
			theme_minimal() +
			theme(axis.title.x = element_text(margin = margin(t = 20), size = 14),
				  axis.title.y = element_text(margin = margin(r = 20), size = 14),
				  axis.text.x = element_text(size = 12),
				  axis.text.y = element_text(size = 12))
	save_pdf(plot_, url_output("byclone", "number_clones_weighted_distance.pdf"), width = 4, height = 4)

	grp = cutree(hc, h = opt$clone_height)
	grp = dplyr::tibble(barcode_id = names(grp),
						clone_id = grp) %>%
		  dplyr::left_join(manifest %>%
						   dplyr::select(barcode_id, best_ploidy_estimate, number_of_segments),
						   by = "barcode_id")

	clone_ord = grp %>%
				dplyr::group_by(clone_id) %>%
				dplyr::summarize(mean_ploidy = round(mean(best_ploidy_estimate)),
								 number_cells = n()) %>%
				dplyr::arrange(mean_ploidy, desc(number_cells))

	grp = grp %>%
		  dplyr::mutate(clone_id = factor(clone_id, levels = rev(clone_ord$clone_id), ordered = TRUE)) %>%
		  dplyr::arrange(clone_id)

	# NEW: keep the cell-to-clone assignments
	readr::write_tsv(x = grp, file = url_output("byclone", "clone_assignments.txt"), append = FALSE, col_names = TRUE)

	# 3. Plot clone CN heatmap ————————————————————————————————————————————————————————————
	copy_number = fit %>%
				  fuzzyjoin::genome_left_join(log2_ratio %>%
											  dplyr::select(Chromosome = chromosome,
															Start_Position = position,
															End_Position = position),
											  by = c("Chromosome", "Start_Position", "End_Position")) %>%
				  dplyr::mutate(Start_Position.x = Start_Position.y) %>%
				  dplyr::select(-`Chromosome.y`,
								-`Start_Position.y`,
								-`End_Position.y`,
								-`End_Position.x`) %>%
				  dplyr::rename(Chromosome = Chromosome.x, Position = Start_Position.x) %>%
				  reshape2::melt(id.vars = c("Chromosome", "Position"), variable.name = "barcode_id", value.name = "CN") %>%
				  dplyr::mutate(CN = pmin(CN, opt$max_copies)) %>%
				  reshape2::dcast(Chromosome + Position ~ barcode_id, value.var = "CN") %>%
				  dplyr::mutate(Chromosome = factor(Chromosome, levels = chromosomes, ordered = TRUE),
								Position = as.numeric(Position)) %>%
				  dplyr::arrange(Chromosome, Position)

	cluster_palette = colorRampPalette(brewer.pal(9, "Set1"))(nrow(clone_ord))
	names(cluster_palette) = sort(clone_ord$clone_id)

	ploidy_palette = colorRampPalette(brewer.pal(12, "Set3"))(length(unique(clone_ord$mean_ploidy)))
	names(ploidy_palette) = sort(unique(clone_ord$mean_ploidy))

	# FIXME (kept as in 06_clonal_decomposition.R): the list name `Plopidy` below does not match
	# the annotation name `Ploidy`, so ploidy_palette is never applied to the Ploidy annotation.
	ha = rowAnnotation(
		`Clone ID` = as.character(grp %>% .[["clone_id"]]),
		`Ploidy`   = as.character(round(grp %>% .[["best_ploidy_estimate"]])),
		col = list(`Clone ID` = cluster_palette,
				   `Plopidy` = ploidy_palette),
		show_annotation_name = FALSE,
		simple_anno_size = unit(3, "mm"),
		annotation_legend_param = list(grid_height = unit(4, "mm"), grid_width = unit(4, "mm"))
	)

	pdf(url_output("byclone", "aggregated_cells_absolute_copies.pdf"), width = 7*2.5, height = 7*1.25)
	draw(Heatmap(matrix = copy_number %>%
						  dplyr::select(grp$barcode_id) %>%
						  t(),
				 col = cn_colors[as.character(0:opt$max_copies)],
				 name = "CN",
				 na_col = "#f0f0f0",
				 rect_gp = gpar(col = NA, lwd = 0),
				 border = NA,

				 cluster_rows = FALSE,
				 row_split = grp$clone_id,
				 show_row_names = FALSE,
				 row_title_gp = gpar(fontsize = 10),
				 row_title_rot = 0,
				 cluster_row_slices = TRUE,
				 clustering_distance_rows = "manhattan",
				 clustering_method_rows = "ward.D",
				 show_row_dend = FALSE,

				 cluster_columns = FALSE,
				 column_split = copy_number %>% .[["Chromosome"]],
				 show_column_names = FALSE,
				 column_title_side = "bottom",
				 column_title_gp = gpar(fontsize = 12),

				 left_annotation = ha,

				 use_raster = FALSE,
				 show_heatmap_legend = TRUE,
				 heatmap_legend_param = list(legend_height = unit(1, "cm"), legend_width = unit(1, "cm"))))
	dev.off()
}

#==================================================
# Dispatch
#==================================================
switch(as.character(opt$option),
	"1" = run_qc(),
	"2" = run_log2_plots(),
	"3" = run_ploidy(),
	"4" = run_absolute_plots(),
	"5" = run_heatmap(),
	"6" = run_bygene_tables(),
	"7" = run_bygene_plots(),
	"8" = run_clones()
)
