# Guards the package-site _quarto.yml against edits that break the Pages artifact flow.
# Run from the package root before `quarto render ui/www`.
args <- commandArgs(trailingOnly = TRUE)
path <- if (length(args)) args[1] else "ui/www/_quarto.yml"
cfg <- yaml::read_yaml(path)
problems <- character(0)
if (!identical(cfg$project$`output-dir`, "_site")) problems <- c(problems, "project.output-dir must be _site")
if (!any(grepl("^assets/fonts/", unlist(cfg$project$resources)))) {
  problems <- c(problems, "project.resources must include assets/fonts/**")
}
covers_hero <- function (res) 
{
    res <- unlist(res)
    if (!is.character(res)) {
        return(FALSE)
    }
    res <- sub("^\\./", "", res)
    target <- "assets/hero/hero.js"
    any(vapply(res, function(e) {
        base <- sub("(/\\*\\*|/)$", "", e)
        if (base %in% c("assets", "assets/hero", target)) {
            return(TRUE)
        }
        if (!grepl("*", e, fixed = TRUE)) {
            return(FALSE)
        }
        rx <- gsub("([.+?^${}()|\\[\\]\\\\])", "\\\\\\1", e)
        rx <- gsub("/**/", "\002", rx, fixed = TRUE)
        rx <- gsub("**", "\001", rx, fixed = TRUE)
        rx <- gsub("*", "[^/]*", rx, fixed = TRUE)
        rx <- gsub("\001", ".*", rx, fixed = TRUE)
        rx <- gsub("\002", "(/.*)?/", rx, fixed = TRUE)
        grepl(paste0("^", rx, "$"), target)
    }, logical(1)))
}
site_dir <- dirname(path)
hero_js <- list.files(file.path(site_dir, "assets", "hero"), pattern = "\\.m?js$", recursive = TRUE)
if (length(hero_js) && !covers_hero(cfg$project$resources)) {
  problems <- c(problems, "project.resources must include assets/hero/** (a JS hero is loaded by import(), which Quarto does not publish)")
}
if (is.null(cfg$format$`pkgsite-html`)) problems <- c(problems, "format must be pkgsite-html")
if (!is.null(cfg$website$navbar$title) && is.null(cfg$website$`site-url`)) problems <- c(problems, "website.site-url is missing")
if (length(problems)) {
  message(paste0("- ", problems, collapse = "\n"))
  quit(status = 1)
}
message("_quarto.yml ok")
