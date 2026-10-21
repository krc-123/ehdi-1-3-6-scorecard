# ------------------------------------------------------------------
# EHDI 1-3-6 scorecard: how every state has done on newborn hearing
# screening by 1 month, diagnosis by 3 months, and early intervention
# by 6 months, 2015 to 2022
#
# analysis.R
# Reads data/ehdi_panel.csv (built by scripts/build_panel.py from CDC's
# Hearing Screening and Follow-up Survey tables) and data/covariates.csv.
# Writes output/ and figures/.
#
# Run in RStudio: open this file, Session > Set Working Directory >
# To Source File Location, then Source (Ctrl+Shift+S).
# ------------------------------------------------------------------

needed <- c("tidyverse", "scales", "estimatr", "ggrepel")
missing <- needed[!needed %in% rownames(installed.packages())]
if (length(missing) > 0) install.packages(missing)
library(tidyverse); library(scales); library(estimatr); library(ggrepel)
have_usmap <- requireNamespace("usmap", quietly = TRUE)

dir.create("output", showWarnings = FALSE); dir.create("figures", showWarnings = FALSE)

panel <- read_csv("data/ehdi_panel.csv", show_col_types = FALSE)
cov   <- read_csv("data/covariates.csv",  show_col_types = FALSE)

states <- panel %>% filter(is_state_or_dc) %>%
  left_join(cov, by = "state") %>%
  mutate(expansion_year = year(as.Date(medicaid_expansion_date)),
         expanded = !is.na(expansion_year) & year >= expansion_year,
         # Expansion in the second half of a year counts from the next birth cohort
         expanded = if_else(!is.na(medicaid_expansion_date) & month(as.Date(medicaid_expansion_date)) > 6 & year == expansion_year, FALSE, expanded))

metrics <- c(
  pct_screened_by_1mo_of_births = "Screened by 1 month (% of births)",
  pct_hl_dx_by_3mo              = "Diagnosed by 3 months (% of infants with hearing loss)",
  pct_ei_by_6mo_of_hl           = "In early intervention by 6 months (% of infants with hearing loss)",
  pct_dx_lfu                    = "Lost to follow-up before diagnosis (% of infants not passing screen)",
  pct_ei_lfu                    = "Lost to follow-up before intervention (% of infants with hearing loss)",
  pct_ei_enrolled               = "Enrolled in early intervention at any age (% of infants with hearing loss)"
)
core3 <- names(metrics)[1:3]

theme_set(theme_minimal(base_size = 13) + theme(panel.grid.minor = element_blank(), plot.title.position = "plot",
                                                 plot.caption = element_text(color = "grey40", hjust = 0)))
cap <- str_wrap("Source: CDC Hearing Screening and Follow-up Survey, annual state tables 2015 to 2022, 50 states and DC. Rates computed from the published counts so the definition is the same in every year.", 120)
pal <- c("#1b7837", "#762a83", "#2166ac", "#c51b8a", "#e08214", "#4d4d4d")

# ---- 1. National picture: median and interquartile range across states ----
long <- states %>% select(state, year, all_of(names(metrics))) %>%
  pivot_longer(-c(state, year), names_to = "metric", values_to = "value") %>%
  filter(!is.na(value)) %>% mutate(metric_label = factor(metrics[metric], levels = metrics))

trend <- long %>% group_by(metric, metric_label, year) %>%
  summarise(n = n(), median = median(value), q25 = quantile(value, .25), q75 = quantile(value, .75),
            min = min(value), max = max(value), .groups = "drop")
write_csv(trend, "output/national_trend_median_iqr.csv")

fig1 <- trend %>% filter(metric %in% core3) %>%
  ggplot(aes(x = year, y = median, color = metric_label, fill = metric_label)) +
  geom_ribbon(aes(ymin = q25, ymax = q75), alpha = 0.15, color = NA) +
  geom_line(linewidth = 1.1) + geom_point(size = 2) +
  scale_color_manual(values = pal[1:3], name = NULL) + scale_fill_manual(values = pal[1:3], name = NULL) +
  scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  scale_x_continuous(breaks = 2015:2022) +
  labs(title = "The 1 is solved. The 3 and the 6 are not.",
       subtitle = "Median state, with the middle half of states shaded",
       x = NULL, y = NULL, caption = cap) +
  theme(legend.position = "top", legend.direction = "vertical")
ggsave("figures/fig1_national_trend.png", fig1, width = 10, height = 7, dpi = 150, bg = "white")

# ---- 2. Change from 2015 to 2022, by state ----------------------
change <- states %>% filter(year %in% c(2015, 2022)) %>%
  select(state, jurisdiction, year, all_of(core3), pct_dx_lfu, pct_ei_lfu, hearing_loss, births_ehdi) %>%
  pivot_wider(names_from = year, values_from = c(all_of(core3), pct_dx_lfu, pct_ei_lfu, hearing_loss, births_ehdi)) %>%
  mutate(d_screen1 = pct_screened_by_1mo_of_births_2022 - pct_screened_by_1mo_of_births_2015,
         d_dx3     = pct_hl_dx_by_3mo_2022 - pct_hl_dx_by_3mo_2015,
         d_ei6     = pct_ei_by_6mo_of_hl_2022 - pct_ei_by_6mo_of_hl_2015,
         d_dx_lfu  = pct_dx_lfu_2022 - pct_dx_lfu_2015) %>%
  arrange(desc(d_ei6))
write_csv(change, "output/change_2015_to_2022.csv")

fig2 <- change %>% filter(!is.na(d_ei6)) %>%
  mutate(jurisdiction = fct_reorder(jurisdiction, d_ei6), dir = if_else(d_ei6 >= 0, "Improved", "Went backward")) %>%
  ggplot(aes(x = d_ei6, y = jurisdiction, color = dir)) +
  geom_segment(aes(x = 0, xend = d_ei6, yend = jurisdiction), color = "grey75") + geom_point(size = 3) +
  scale_color_manual(values = c(Improved = "#1b7837", `Went backward` = "#c51b8a"), name = NULL) +
  scale_x_continuous(labels = function(x) paste0(ifelse(x > 0, "+", ""), x, " pts")) +
  labs(title = "Change in the share of deaf and hard of hearing infants enrolled in early intervention by 6 months, 2015 to 2022",
       subtitle = "Percentage points. The 6 in 1-3-6, measured against every infant diagnosed with hearing loss.",
       x = NULL, y = NULL, caption = cap) +
  theme(legend.position = "top", axis.text.y = element_text(size = 9))
ggsave("figures/fig2_change_ei_by_6mo.png", fig2, width = 10, height = 12, dpi = 150, bg = "white")

# ---- 3. The 2022 scorecard -----------------------------------------
score <- states %>% filter(year == 2022) %>%
  select(state, jurisdiction, births_ehdi, hearing_loss, all_of(names(metrics))) %>%
  mutate(across(all_of(names(metrics)), ~ round(.x, 1))) %>%
  # Simple composite: average of the three benchmark rates
  mutate(composite = round((pct_screened_by_1mo_of_births + pct_hl_dx_by_3mo + pct_ei_by_6mo_of_hl) / 3, 1)) %>%
  arrange(desc(composite)) %>% mutate(rank = row_number())
write_csv(score, "output/scorecard_2022.csv")

fig3 <- score %>% filter(!is.na(composite)) %>%
  select(jurisdiction, composite, all_of(core3)) %>%
  pivot_longer(all_of(core3), names_to = "metric", values_to = "value") %>%
  mutate(metric_label = factor(metrics[metric], levels = metrics[core3]), jurisdiction = fct_reorder(jurisdiction, composite)) %>%
  ggplot(aes(x = value, y = jurisdiction, color = metric_label)) +
  geom_point(size = 2.6, alpha = 0.9) +
  scale_color_manual(values = pal[1:3], name = NULL) +
  scale_x_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(title = "2022 scorecard: the three benchmarks, every state",
       subtitle = "Ordered by the average of the three. Screening is near 100 everywhere; the spread is in diagnosis and intervention.",
       x = NULL, y = NULL, caption = cap) +
  theme(legend.position = "top", legend.direction = "vertical", axis.text.y = element_text(size = 8.5))
ggsave("figures/fig3_scorecard_2022.png", fig3, width = 10, height = 12, dpi = 150, bg = "white")

# ---- 4. Loss to follow-up heatmap ---------------------------------
order_lfu <- states %>% filter(year == 2022) %>% arrange(pct_dx_lfu) %>% pull(jurisdiction)
fig4 <- states %>% filter(!is.na(pct_dx_lfu)) %>%
  mutate(jurisdiction = factor(jurisdiction, levels = rev(order_lfu))) %>%
  ggplot(aes(x = factor(year), y = jurisdiction, fill = pct_dx_lfu)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = round(pct_dx_lfu), color = pct_dx_lfu > 45), size = 2.8) +
  scale_fill_gradient(low = "#f7f4f9", high = "#7a0177", name = "% lost", limits = c(0, 100)) +
  scale_color_manual(values = c(`TRUE` = "white", `FALSE` = "black"), guide = "none") +
  scale_x_discrete(position = "top") +
  labs(title = "Lost before diagnosis: share of infants who did not pass the screen and were never documented as diagnosed",
       subtitle = "Ordered by 2022. Blank = state did not report that year.", x = NULL, y = NULL, caption = cap) +
  theme(panel.grid = element_blank(), axis.text.y = element_text(size = 8.5))
ggsave("figures/fig4_diagnostic_lfu_heatmap.png", fig4, width = 9, height = 13, dpi = 150, bg = "white")

# ---- 5. Does Medicaid expansion move the numbers? -----------------
# Two-way fixed effects (state and year) on the state-year panel, standard
# errors clustered by state. Identification comes from the states that
# expanded inside the window (PA, IN, AK 2015; MT, LA 2016; VA, ME 2019;
# ID, UT 2020; NE 2020-21; OK, MO 2021-22), compared with states that had
# already expanded and states that never did. Treat as descriptive: the
# switchers are few and the outcomes are noisy in small states.
twfe <- map_dfr(names(metrics), function(m) {
  d <- states %>% filter(!is.na(.data[[m]]))
  fit <- lm_robust(as.formula(paste(m, "~ expanded")), data = d, fixed_effects = ~ state + year, clusters = state, se_type = "stata")
  tibble(metric = m, metric_label = metrics[m], estimate = coef(fit)[["expandedTRUE"]],
         se = fit$std.error[["expandedTRUE"]], ci_low = fit$conf.low[["expandedTRUE"]], ci_high = fit$conf.high[["expandedTRUE"]],
         p = fit$p.value[["expandedTRUE"]], n_obs = nobs(fit), n_switchers = n_distinct(d$state[d$expansion_year %in% 2015:2022]))
})
write_csv(twfe, "output/twfe_medicaid_expansion.csv")

fig5 <- twfe %>% mutate(metric_label = fct_rev(factor(metric_label, levels = metrics))) %>%
  ggplot(aes(x = estimate, y = metric_label)) +
  geom_vline(xintercept = 0, color = "grey50") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.2, orientation = "y", color = "grey40") +
  geom_point(size = 3, color = "#762a83") +
  scale_x_continuous(labels = function(x) paste0(ifelse(x > 0, "+", ""), x, " pts")) +
  labs(title = "Medicaid expansion and the EHDI benchmarks: two-way fixed effects estimates",
       subtitle = sprintf("Percentage-point change after a state expands, with 95%% intervals (state-clustered). %d states expanded during 2015 to 2022.", twfe$n_switchers[1]),
       x = NULL, y = NULL, caption = cap) +
  theme(axis.text.y = element_text(size = 10))
ggsave("figures/fig5_medicaid_expansion_twfe.png", fig5, width = 10, height = 6, dpi = 150, bg = "white")

# Cross-sectional comparison for the README (2022, expanded vs not)
xs <- states %>% filter(year == 2022) %>% group_by(expansion_status_2022) %>%
  summarise(states = n(), across(all_of(names(metrics)), ~ round(median(.x, na.rm = TRUE), 1)), .groups = "drop")
write_csv(xs, "output/expansion_status_2022_medians.csv")

# ---- 6. Map (optional) ---------------------------------------------
if (have_usmap) tryCatch({
  m <- usmap::plot_usmap(data = score %>% select(state, pct_ei_by_6mo_of_hl), values = "pct_ei_by_6mo_of_hl", regions = "states", color = "white") +
    scale_fill_gradient(low = "#f7fcf5", high = "#00441b", name = "% in EI\nby 6 months", na.value = "grey90") +
    labs(title = "Deaf and hard of hearing infants enrolled in early intervention by 6 months, 2022", caption = cap)
  ggsave("figures/fig6_map_ei_by_6mo_2022.png", m, width = 10, height = 6.5, dpi = 150, bg = "white")
}, error = function(e) message("Map skipped: ", conditionMessage(e)))

# ---- 7. Headline numbers and README tables ----------------------
s22 <- states %>% filter(year == 2022); s15 <- states %>% filter(year == 2015)
hl <- c(
  sprintf("State-years in panel: %d (%d states and DC, 2015 to 2022); territories kept in data/ehdi_panel.csv but excluded here", nrow(states), n_distinct(states$state)),
  sprintf("Births covered in 2022: %s; infants diagnosed deaf or hard of hearing: %s", comma(sum(s22$births_ehdi, na.rm = TRUE)), comma(sum(s22$hearing_loss, na.rm = TRUE))),
  sprintf("Median state 2022: screened by 1 month %.1f%%; diagnosed by 3 months %.1f%%; in EI by 6 months %.1f%%", median(s22$pct_screened_by_1mo_of_births, na.rm = TRUE), median(s22$pct_hl_dx_by_3mo, na.rm = TRUE), median(s22$pct_ei_by_6mo_of_hl, na.rm = TRUE)),
  sprintf("Median state 2015: screened by 1 month %.1f%%; diagnosed by 3 months %.1f%%; in EI by 6 months %.1f%%", median(s15$pct_screened_by_1mo_of_births, na.rm = TRUE), median(s15$pct_hl_dx_by_3mo, na.rm = TRUE), median(s15$pct_ei_by_6mo_of_hl, na.rm = TRUE)),
  sprintf("Median diagnostic loss to follow-up 2022: %.1f%% (range %.1f to %.1f)", median(s22$pct_dx_lfu, na.rm = TRUE), min(s22$pct_dx_lfu, na.rm = TRUE), max(s22$pct_dx_lfu, na.rm = TRUE)),
  sprintf("States where EI-by-6-months improved 2015 to 2022: %d; went backward: %d", sum(change$d_ei6 > 0, na.rm = TRUE), sum(change$d_ei6 < 0, na.rm = TRUE)),
  sprintf("States with at least 80%% of diagnosed infants in EI by 6 months in 2022: %d; below 30%%: %d", sum(s22$pct_ei_by_6mo_of_hl >= 80, na.rm = TRUE), sum(s22$pct_ei_by_6mo_of_hl < 30, na.rm = TRUE))
)
writeLines(hl, "output/headline_numbers.txt"); cat(paste(hl, collapse = "\n"), "\n")

md_table <- function(df) {
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |"); sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  paste(c(hdr, sep, apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
}
t_top <- score %>% slice_head(n = 10) %>% transmute(Rank = rank, State = jurisdiction, `Screened by 1 mo` = pct_screened_by_1mo_of_births, `Diagnosed by 3 mo` = pct_hl_dx_by_3mo, `EI by 6 mo` = pct_ei_by_6mo_of_hl, `Lost before dx` = pct_dx_lfu, `Infants D/HH` = hearing_loss)
t_bot <- score %>% filter(!is.na(composite)) %>% slice_tail(n = 10) %>% transmute(Rank = rank, State = jurisdiction, `Screened by 1 mo` = pct_screened_by_1mo_of_births, `Diagnosed by 3 mo` = pct_hl_dx_by_3mo, `EI by 6 mo` = pct_ei_by_6mo_of_hl, `Lost before dx` = pct_dx_lfu, `Infants D/HH` = hearing_loss)
t_up <- change %>% filter(!is.na(d_ei6)) %>% slice_head(n = 8) %>% transmute(State = jurisdiction, `EI by 6 mo, 2015` = round(pct_ei_by_6mo_of_hl_2015, 1), `EI by 6 mo, 2022` = round(pct_ei_by_6mo_of_hl_2022, 1), Change = paste0("+", round(d_ei6, 1)))
t_down <- change %>% filter(!is.na(d_ei6)) %>% slice_tail(n = 8) %>% transmute(State = jurisdiction, `EI by 6 mo, 2015` = round(pct_ei_by_6mo_of_hl_2015, 1), `EI by 6 mo, 2022` = round(pct_ei_by_6mo_of_hl_2022, 1), Change = round(d_ei6, 1))
t_twfe <- twfe %>% transmute(Outcome = metric_label, Estimate = paste0(ifelse(estimate > 0, "+", ""), round(estimate, 1), " pts"), `95% CI` = paste0(round(ci_low, 1), " to ", round(ci_high, 1)), p = round(p, 2))
t_xs <- xs %>% transmute(`Expansion status (2022)` = expansion_status_2022, States = states, `Screened by 1 mo` = pct_screened_by_1mo_of_births, `Diagnosed by 3 mo` = pct_hl_dx_by_3mo, `EI by 6 mo` = pct_ei_by_6mo_of_hl, `Lost before dx` = pct_dx_lfu)
writeLines(c("## Top ten, 2022", md_table(t_top), "", "## Bottom ten, 2022", md_table(t_bot), "", "## Biggest improvements in EI by 6 months", md_table(t_up), "", "## Biggest declines", md_table(t_down), "", "## Medicaid expansion, two-way fixed effects", md_table(t_twfe), "", "## 2022 medians by expansion status", md_table(t_xs)), "output/readme_tables.md")
message("Done.")
