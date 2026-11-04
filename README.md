# Yelp New Orleans Restaurant Analysis

This repository contains the data-import and filtering work for Homework 5 and the Yelp New Orleans Restaurant Analysis project.

## Homework 5 completed steps

1. Created a new GitHub repository/project directory.
2. Downloaded and extracted the Yelp Open Dataset.
3. Imported the large business and review JSON files into R.
4. Filtered the business data to New Orleans restaurants.
5. Filtered the review data to reviews associated with those restaurants.
6. Saved the filtered data as compressed RDS files.

## Data

The original Yelp JSON files are not committed because they are several gigabytes in size. Download the JSON archive from the [Yelp Open Dataset](https://business.yelp.com/data/resources/open-dataset/) page and extract these files into `data/raw/`:

- `yelp_academic_dataset_business.json`
- `yelp_academic_dataset_review.json`

Filtered outputs are saved in `data/new_orleans/`.

## Reproduce the data preparation

From the project root, run:

```r
source("R/import_filter.R")
```

The review file is processed in chunks to reduce memory use. The import may take several minutes.

## Files

- `R/import_filter.R`: imports, filters, validates, and saves the data.
- `data/new_orleans/business_new_orleans.rds`: New Orleans restaurant businesses.
- `data/new_orleans/reviews_new_orleans.rds`: reviews for the retained restaurants.
- `data/new_orleans/import_summary.txt`: row counts and basic validation results.

