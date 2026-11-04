suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(stringr)
})

business_file <- "data/raw/yelp_academic_dataset_business.json"
review_file <- "data/raw/yelp_academic_dataset_review.json"

required_files <- c(business_file, review_file)
missing_files <- required_files[!file.exists(required_files)]

if (length(missing_files) > 0) {
  stop(
    "Missing required raw file(s): ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

dir.create("data/new_orleans", recursive = TRUE, showWarnings = FALSE)
dir.create("data/tmp/review_chunks", recursive = TRUE, showWarnings = FALSE)

message("Importing Yelp business data...")

business_connection <- file(business_file, open = "r")
business_raw <- stream_in(business_connection, verbose = FALSE)
close(business_connection)

new_orleans_restaurants <- business_raw |>
  select(
    business_id, name, address, city, state, postal_code,
    latitude, longitude, stars, review_count, categories
  ) |>
  filter(
    state == "LA",
    city == "New Orleans",
    !is.na(categories),
    str_detect(categories, regex("Restaurants", ignore_case = TRUE))
  ) |>
  mutate(
    postal_code = na_if(postal_code, ""),
    categories = str_squish(categories),
    business_name = str_squish(name)
  ) |>
  distinct(business_id, .keep_all = TRUE)

if (nrow(new_orleans_restaurants) == 0) {
  stop("The business filter returned zero New Orleans restaurants.", call. = FALSE)
}

saveRDS(
  new_orleans_restaurants,
  "data/new_orleans/business_new_orleans.rds",
  compress = "xz"
)

restaurant_ids <- new_orleans_restaurants$business_id
chunk_number <- 0L
matched_review_rows <- 0L

message("Streaming Yelp reviews and retaining New Orleans restaurant reviews...")

review_connection <- file(review_file, open = "r")

stream_in(
  review_connection,
  pagesize = 50000,
  verbose = TRUE,
  handler = function(page) {
    filtered_page <- page |>
      filter(business_id %in% restaurant_ids) |>
      select(business_id, user_id, stars, date, text, useful, funny, cool)

    if (nrow(filtered_page) > 0) {
      chunk_number <<- chunk_number + 1L
      matched_review_rows <<- matched_review_rows + nrow(filtered_page)

      saveRDS(
        filtered_page,
        sprintf("data/tmp/review_chunks/chunk_%04d.rds", chunk_number),
        compress = FALSE
      )
    }
  }
)

close(review_connection)

chunk_files <- list.files(
  "data/tmp/review_chunks",
  pattern = "^chunk_[0-9]+[.]rds$",
  full.names = TRUE
)

if (length(chunk_files) == 0) {
  stop("No matching reviews were found.", call. = FALSE)
}

message("Combining ", length(chunk_files), " filtered review chunks...")

new_orleans_reviews <- chunk_files |>
  lapply(readRDS) |>
  bind_rows()

if (nrow(new_orleans_reviews) != matched_review_rows) {
  stop("Review row-count validation failed.", call. = FALSE)
}

if (!all(new_orleans_reviews$business_id %in% restaurant_ids)) {
  stop("Review business-ID validation failed.", call. = FALSE)
}

saveRDS(
  new_orleans_reviews,
  "data/new_orleans/reviews_new_orleans.rds",
  compress = "xz"
)

summary_lines <- c(
  paste("New Orleans restaurants:", nrow(new_orleans_restaurants)),
  paste("New Orleans restaurant reviews:", nrow(new_orleans_reviews)),
  paste("Distinct reviewed restaurants:", n_distinct(new_orleans_reviews$business_id)),
  paste("Distinct reviewers:", n_distinct(new_orleans_reviews$user_id)),
  paste("Missing latitude:", sum(is.na(new_orleans_restaurants$latitude))),
  paste("Missing longitude:", sum(is.na(new_orleans_restaurants$longitude)))
)

writeLines(summary_lines, "data/new_orleans/import_summary.txt")
message(paste(summary_lines, collapse = "\n"))
message("Homework 5 data preparation completed successfully.")
