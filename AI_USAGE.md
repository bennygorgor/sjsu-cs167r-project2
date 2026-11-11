# AI use and actual prompts

Codex assisted with R code, geographic data acquisition, debugging, report drafting, figures and validation. All numerical findings in the report are computed from the committed RDS inputs and official 2024 Census boundary archives. The report is a generated artifact of `R/homework6.R`.

## Examples from the conversation
1. “Compare Census tracts and block groups for the selected New Orleans restaurants. Include restaurant counts, average ratings, review volume, and maps, then explain which geographic system is more suitable.”

2. Follow-up: “Check whether the analysis meets the Homework 6 requirements. Verify the geographic assignments, identify unmatched restaurants, and explain any limitations.”
   
- Homework 5 request: Please analyze the type of data contained therein.
- Review request: "Does this meet the requirements? Could you please check it for me again?" (This prompted a review of the filtering process, review IDs, the readability of the RDS files, and the contents of the GitHub repository.)
- Homework 6 context: — referring to the Homework 6 screenshot: Select a geographic area, justify your choice (following the steps up to Step 6), and include a table and/or maps. Please let me know which option you think is a good choice and explain why.

## Decisions and revisions during this work

The user suggested Seafood and Southern as the main categories. Codex added Cajun/Creole to develop a related regional-food theme and compared Census tracts with block groups before selecting tracts based on restaurant counts and sparsity. An initial substring search found 332 Seafood-related businesses; exact matching of comma-separated category labels identified 331 businesses labeled Seafood, excluding businesses whose labels only contained the word “Seafood,” such as Seafood Markets.

An initial area-summary run failed because a summed review-count column shadowed the original weights inside `summarise()`. The calculation order was corrected so the weighted rating uses each restaurant's review count before that column is aggregated. The final script was rerun successfully.

Boundary mismatches were retained in audit tables rather than discarded. The resulting report distinguishes Yelp city labels, official place polygons and Orleans Parish statistical areas. No reviewer-normalized score or final recommendation is claimed at this stage.
