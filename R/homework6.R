# Run from the repository root: Rscript R/homework6.R
suppressPackageStartupMessages({library(tidyverse); library(sf)})
options(scipen=999)
dir.create("tables", showWarnings=FALSE)
dir.create("figures", showWarnings=FALSE)
dir.create("reports", showWarnings=FALSE)
dir.create("data/boundaries", recursive=TRUE, showWarnings=FALSE)
theme_set(theme_minimal(base_size=12) + theme(panel.grid.minor=element_blank(),
  plot.title=element_text(face="bold"), plot.background=element_rect(fill="white",color=NA)))
b <- readRDS("data/new_orleans/business_new_orleans.rds")
r <- readRDS("data/new_orleans/reviews_new_orleans.rds")
categories <- b |> select(business_id,categories) |>
  separate_longer_delim(categories, delim=",") |>
  transmute(business_id,category=str_to_lower(str_squish(categories))) |> distinct()
chosen <- c("seafood","cajun/creole","southern")
counts <- categories |> count(category,sort=TRUE)
write_csv(counts,"tables/category_counts.csv")
chosen_counts <- counts |> filter(category %in% chosen)
pairs <- inner_join(categories,categories,by="business_id",relationship="many-to-many") |>
  filter(category.x < category.y) |> count(category.x,category.y,sort=TRUE)
write_csv(pairs,"tables/category_pairs.csv")
chosen_pairs <- pairs |> filter(category.x %in% chosen,category.y %in% chosen)
selected <- b |> semi_join(filter(categories,category %in% chosen),by="business_id")
# Keep every available review for every qualifying restaurant before summarizing.
cr <- r |> semi_join(selected,by="business_id")
review_summary <- cr |> group_by(business_id) |>
  summarise(available_reviews=n(),review_mean=mean(stars),.groups="drop")
selected <- selected |> left_join(review_summary,by="business_id")
stopifnot(!anyDuplicated(selected$business_id), all(cr$business_id %in% selected$business_id))
write_csv(review_summary,"tables/review_summary.csv")
bound <- function(kind) {
  path <- paste0("data/boundaries/",kind,".zip")
  url <- paste0("https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_22_",kind,"_500k.zip")
  if(!file.exists(path)) download.file(url,path,mode="wb")
  dest <- paste0("data/boundaries/",kind)
  dir.create(dest,showWarnings=FALSE)
  unzip(path,exdir=dest)
  st_read(list.files(dest,pattern="[.]shp$",full.names=TRUE),quiet=TRUE) |>
    st_make_valid() |> st_transform(26915)
}
places <- bound("place")
tracts <- bound("tract") |> filter(COUNTYFP=="071")
bgs <- bound("bg") |> filter(COUNTYFP=="071")
city <- places |> filter(NAME=="New Orleans")
points <- b |> st_as_sf(coords=c("longitude","latitude"),crs=4326,remove=FALSE) |> st_transform(26915)
place_join <- st_join(points,places |> select(place_geoid=GEOID,place_name=NAME),join=st_within)
stopifnot(nrow(place_join)==nrow(b))
place_check <- place_join |> st_drop_geometry() |> count(city,place_name,name="restaurants",sort=TRUE)
write_csv(place_check,"tables/place_comparison.csv")
mismatch <- place_join |> filter(is.na(place_name)|place_name!="New Orleans")
if(nrow(mismatch)>0) {
  mismatch$distance_to_city_m <- as.numeric(st_distance(mismatch,st_union(city)))
}
write_csv(st_drop_geometry(mismatch),"tables/place_mismatches.csv")
# Explicit scope: retain the Yelp city-label universe for the comparison;
# Orleans Parish polygons define the candidate areas. Outside points remain NA.
sp <- points |> semi_join(selected,by="business_id") |>
  left_join(review_summary,by="business_id")
systems <- list("Census tracts"=tracts,"Census block groups"=bgs)
comparisons <- list(); area_tables <- list(); joins <- list()
for(system in names(systems)) {
  polys <- systems[[system]] |> transmute(area_id=GEOID,area_name=NAME)
  joined <- st_join(sp,polys,join=st_within,left=TRUE)
  stopifnot(nrow(joined)==nrow(sp))
  stats <- joined |> st_drop_geometry() |> filter(!is.na(area_id)) |>
    group_by(area_id,area_name) |> summarise(restaurants=n(),
      mean_business_stars=mean(stars),median_business_stars=median(stars),
      review_weighted_stars=weighted.mean(review_mean,available_reviews),
      available_reviews=sum(available_reviews),.groups="drop")
  allareas <- polys |> st_drop_geometry() |> left_join(stats,by=c("area_id","area_name")) |>
    mutate(restaurants=replace_na(restaurants,0L),available_reviews=replace_na(available_reviews,0L)) |>
    arrange(desc(restaurants))
  slug <- if(system=="Census tracts") "tracts" else "block_groups"
  write_csv(allareas,paste0("tables/",slug,"_summary.csv"))
  write_csv(joined |> st_drop_geometry(),paste0("tables/",slug,"_assignments.csv"))
  comparisons[[system]] <- tibble(system=system,total_areas=nrow(polys),
    occupied_areas=nrow(stats),assigned=sum(!is.na(joined$area_id)),
    unmatched=sum(is.na(joined$area_id)),zero_restaurant_areas=sum(allareas$restaurants==0),
    smallest_occupied_count=min(stats$restaurants),largest_count=max(stats$restaurants),
    occupied_areas_under5=sum(stats$restaurants<5),
    median_occupied_count=median(stats$restaurants))
  area_tables[[system]]<-allareas; joins[[system]]<-joined
  mapdata <- polys |> left_join(allareas,by=c("area_id","area_name"))
  p <- ggplot(mapdata)+geom_sf(aes(fill=restaurants),color="grey65",linewidth=.12)+
    geom_sf(data=sp,color="#b33c2f",size=.45,alpha=.5)+
    scale_fill_viridis_c(option="C",trans="sqrt",limits=c(0,111))+
    labs(title=paste("Local-flavor restaurants:",system),
      subtitle="Seafood, Cajun/Creole or Southern; all Orleans Parish areas shown",
      fill="Restaurants",caption="2024 Census cartographic boundaries; Yelp snapshot, not current openings")+
    theme(axis.text=element_text(size=7))
  ggsave(paste0("figures/",slug,"_map.png"),p,width=10,height=7,dpi=170)
  if(system=="Census tracts") {
    zoom <- p + coord_sf(default_crs=st_crs(4326),xlim=c(-90.15,-90.00),ylim=c(29.90,30.02)) +
      labs(title="Census tracts: central New Orleans detail",
        subtitle="Same counts and color scale; cropped view of the denser restaurant corridor")
    ggsave("figures/tracts_detail.png",zoom,width=9,height=8,dpi=170)
  }
}
comparison <- bind_rows(comparisons)
write_csv(comparison,"tables/geographic_comparison.csv")
stopifnot(nrow(selected)>=10,comparison$occupied_areas[comparison$system=="Census tracts"]>=7)
top <- area_tables[["Census tracts"]] |> filter(restaurants>=5) |>
  arrange(desc(mean_business_stars),desc(restaurants)) |> slice_head(n=10)
p <- ggplot(top,aes(reorder(area_name,mean_business_stars),mean_business_stars))+
  geom_col(fill="#167d8d")+geom_text(aes(label=paste0("n=",restaurants)),hjust=-.15,size=3)+
  coord_flip(ylim=c(0,5))+labs(title="Preliminary tract ratings",subtitle="Only tracts with at least five selected restaurants; not a final best-area ranking",
    x="Census tract",y="Mean business stars (each restaurant weighted equally)")
ggsave("figures/tract_ratings.png",p,width=9,height=6,dpi=170)
plotdata <- bind_rows(lapply(names(area_tables),function(s) mutate(area_tables[[s]],system=s))) |>
  mutate(size_group=cut(restaurants,breaks=c(-1,0,4,9,19,Inf),labels=c("0","1-4","5-9","10-19","20+"))) |>
  count(system,size_group,.drop=FALSE)
p <- ggplot(plotdata,aes(size_group,n,fill=system))+geom_col()+
  geom_text(aes(label=n),vjust=-.4,size=3.5)+
  facet_wrap(~system,ncol=1,scales="free_y")+scale_fill_manual(values=c("#167d8d","#d48a30"))+
  scale_y_continuous(expand=expansion(mult=c(0,.15)))+
  labs(title="How sparse are the candidate areas?",subtitle="All Orleans Parish areas, including zero selected restaurants",
    x="Selected restaurants per area",y="Number of areas")+theme(legend.position="none",plot.margin=margin(15,15,15,15))
ggsave("figures/area_counts.png",p,width=9,height=7,dpi=170)
# Generate a GitHub-native report with results embedded; no execution is needed to view it.
md <- function(df,digits=2) {
  df<-as.data.frame(df)
  df[]<-lapply(df,function(x) if(is.numeric(x)) format(round(x,digits),trim=TRUE,scientific=FALSE) else as.character(x))
  c(paste0("| ",paste(names(df),collapse=" | ")," |"),
    paste0("| ",paste(rep("---",ncol(df)),collapse=" | ")," |"),
    apply(df,1,function(x) paste0("| ",paste(x,collapse=" | ")," |")))
}
t<-comparisons[["Census tracts"]]; g<-comparisons[["Census block groups"]]
doc <- c("# Homework 6: Choosing a geographic area", "",
  "## Decision and research question", "",
  "**Chosen region: New Orleans, Louisiana. Chosen geographic unit: 2024 Census tracts within Orleans Parish (FIPS 22071).**", "",
  "Research question: Where can someone find the best Seafood, Cajun/Creole, or Southern restaurants in New Orleans, and which geographic area is most useful for comparing them?", "",
  sprintf("I choose Census tracts for the main analysis. The selected group includes **%s restaurants and %s available reviews**. Tracts assign %s restaurants across %s occupied areas, compared with %s occupied block groups. The median occupied tract contains %s restaurants; the median occupied block group contains %s. Tracts provide a less fragmented comparison while retaining local detail. This decision is based on sample support and spatial resolution, not the highest ratings.",nrow(selected),nrow(cr),t$assigned,t$occupied_areas,g$occupied_areas,t$median_occupied_count,g$median_occupied_count), "",
  "## Steps 1–2: Data and large-file management", "",
  "Homework 5 imported the complete Yelp business JSON and streamed all 6,990,280 review records in 50,000-record chunks, keeping reviews linked to 2,259 New Orleans restaurant businesses. The resulting RDS files contain 2,259 businesses and 476,421 reviews. Raw JSON files were extracted locally and excluded from GitHub. Chunking avoids holding the entire review database in memory; compressed RDS files reduce storage. No development sample substitutes for the complete New Orleans data. The code and import summary are linked below.", "",
  "The initial definition is `state == 'LA'`, `city == 'New Orleans'`, and a nonmissing categories field containing Restaurants. Duplicate business IDs are removed. Missing postal codes are stored as NA, whitespace is cleaned, and coordinates are checked (no missing coordinates in the retained data). Closed businesses are retained to match the historical review database; this is not a current restaurant directory.", "",
  "## Step 3: A coherent local-flavor category group", "",
  "Seafood, Cajun/Creole and Southern form a New Orleans regional-food theme: seafood is an ingredient focus, Cajun/Creole is a regional cooking tradition, and Southern broadens the regional menu context. They were chosen for that connection, not simply because they are the most frequent labels. Categories are split at commas, trimmed, lowercased and deduplicated per business. Include a restaurant if it has **at least one exact label** in this group.", "",
  md(chosen_counts), "", "Counts overlap; they should not be added to obtain the unique restaurant count.", "",
  "### Category co-occurrence", "", md(chosen_pairs), "",
  "Each pair counts distinct businesses with both labels. Overlap supports a shared regional-food theme, while the OR rule also keeps restaurants specializing in only one of these cuisines. This creates broad coverage without requiring every restaurant to fit all three labels. Full category counts and pair counts are saved as CSV files. Exact-label matching is important: a broad Seafood substring search also captures other labels, whereas the actual Seafood category has 331 restaurants.", "",
  sprintf("The union contains **%s distinct restaurants**. Under the chosen tract system, **%s restaurants occupy %s different tracts**, exceeding the required 10 restaurants and 7 areas. Unmatched restaurants remain explicitly recorded.",nrow(selected),t$assigned,t$occupied_areas), "",
  "## Step 4: Join businesses and reviews", "",
  sprintf("The full New Orleans review RDS is filtered with a semi-join to the selected business IDs before computing review summaries. The group retains **%s reviews for %s businesses**. Review-level stars are summarized per business, then left-joined to business records by business_id, giving one row per restaurant. Geographic review-weighted stars weight these business review means by their actual available review counts. Business-star averages weight each restaurant equally. These measures answer different questions and are not interchangeable.",nrow(cr),nrow(review_summary)), "",
  "## Step 5: Official city boundary check", "",
  "Longitude/latitude are first interpreted as WGS84 (EPSG:4326). Points and polygons are transformed to EPSG:26915 before `sf::st_join(..., join = st_within)`. The initial Yelp city label is compared with all Louisiana place polygons from the 2024 Census cartographic boundary release.", "",md(place_check), "",
  sprintf("**%s restaurant coordinates do not match the New Orleans place polygon.** Individual names, coordinates, matched place labels and distances to the New Orleans polygon are recorded in [the mismatch audit](../tables/place_mismatches.csv). A city-text label is not proof of municipal membership. Possible causes are postal-city labeling, geocoding errors, changed locations, or simplified river/coast boundaries; the available data cannot resolve those causes. I retain the original city-label universe and flag these records rather than silently deleting or moving them. The tract/block-group comparison uses Orleans Parish polygons; points outside them remain unmatched, so the comparisons below use explicitly assigned restaurants.",nrow(mismatch)), "",
  "The mismatches include 18 restaurants in Elmwood, 13 in Jefferson and 10 in Harahan (41 of the 57). These are named outside places, so this pattern is consistent with postal-city labels or geocoding/location issues, rather than only tiny river-edge errors. The audit gives distances so the cases can be investigated individually; it does not establish which explanation is correct.", "",
  "## Step 6: Compare and defend geographic systems", "",
  "Both candidate systems use all 2024 Orleans Parish areas and the identical selected restaurant points. Every polygon is counted, including areas with zero selected restaurants. Occupied areas have at least one. The smallest occupied count excludes zeros; zero areas are reported separately. A restaurant exactly on a shared boundary may remain unmatched under st_within; no nearest-area imputation is used.", "",
  md(comparison |> transmute(System=system,Areas=total_areas,Occupied=occupied_areas,Assigned=assigned,Unmatched=unmatched)), "",
  md(comparison |> transmute(System=system,Zero=zero_restaurant_areas,Min_occupied=smallest_occupied_count,Max=largest_count,Under_5=occupied_areas_under5,Median_occupied=median_occupied_count)), "",
  "![Tract map](../figures/tracts_map.png)", "", "![Block group map](../figures/block_groups_map.png)", "",
  "Maps use the same full-city view, with red points representing selected restaurants. Large low-density areas and the river help explain uneven coverage; the boundaries represent statistical areas, not restaurant-defined districts.", "",
  "![Central New Orleans tract detail](../figures/tracts_detail.png)", "",
  "![Area count distributions](../figures/area_counts.png)", "",
  "### Why Census tracts?", "",
  sprintf("Block groups provide more local detail, but %s of %s occupied block groups have fewer than five selected restaurants. Tracts have %s of %s occupied areas below that threshold. Tracts therefore reduce fragmentation, although sparse tracts still exist. The five-restaurant threshold is an exploratory stability screen, not a statistical guarantee; complete unfiltered area summaries remain available in the CSV files.",g$occupied_areas_under5,g$occupied_areas,t$occupied_areas_under5,t$occupied_areas), "",
  "Tracts support comparisons within a city and have stable geographic identifiers that can be documented and mapped. Their weakness for visitors is unfamiliar numeric labels: they are Census statistical areas, not named neighborhoods. The final report should pair tract GEOIDs with maps and restaurant addresses. Block groups may be useful for later street-scale exploration, but they split the evidence into smaller samples. Neither system describes walkability or equal-sized commercial districts.", "",
  "### Block-group rating evidence", "",
  "For comparison, here are the five block groups with the largest selected-restaurant counts, with their business-star averages and review volume. Full summaries for all block groups and tracts, including zero-count areas and unmatched restaurant assignments, are linked below.", "",
  md(area_tables[["Census block groups"]] |> slice_head(n=5)), "",
  "### Preliminary tract evidence", "",
  "The following ten tracts have the highest mean business ratings among those containing at least five selected restaurants. They are exploratory area summaries, **not the final Top 10 restaurants**. More reviews do not necessarily imply a more representative sample.", "",md(top), "",
  "![Preliminary tract ratings](../figures/tract_ratings.png)", "",
  "## Limitations and next step", "",
  "The Yelp snapshot predates these 2024 boundaries; historical openings, closures and coordinates can disagree with later boundaries. Cartographic boundaries at 1:500,000 simplify geometry, particularly near water. An exact TIGER/Line boundary check would improve borderline assignments. Yelp users and businesses are not a random sample; regional categories are imperfect and can overlap. Small area means can be unstable, and the choice of geographic scale can change the apparent pattern. Ratings alone do not establish a causal effect of location.", "",
  "Reviewer-normalized scores and reviewer-activity sensitivity checks belong to Step 7 and are not yet calculated. This Homework 6 decision uses coverage, counts, business ratings and available review volume. The next stage will test whether restaurant/area conclusions change after reviewer normalization, then develop the final restaurant recommendations.", "",
  "## Reproduce and inspect", "",
  "Install `tidyverse` and `sf`, then from the repository root run `Rscript R/homework6.R`. The two Homework 5 RDS files are inputs. Census ZIP archives are included for reproducibility; the script downloads them from the official URLs if absent. Rendering is unnecessary: this Markdown report, embedded PNG figures and CSV tables are viewable directly on GitHub.", "",
  "- [Homework 5 import source](../R/import_filter.R)",
  "- [Homework 6 analysis source](../R/homework6.R)",
  "- [Geographic comparison CSV](../tables/geographic_comparison.csv)",
  "- [Complete tract summaries](../tables/tracts_summary.csv)",
  "- [Complete block group summaries](../tables/block_groups_summary.csv)",
  "- [Restaurant tract assignments](../tables/tracts_assignments.csv)",
  "- [Category counts](../tables/category_counts.csv)",
  "- [Category co-occurrence counts](../tables/category_pairs.csv)", "",
  "## Sources", "",
  "- [Yelp Open Dataset](https://business.yelp.com/data/resources/open-dataset/)",
  "- [Census 2024 cartographic boundary files](https://www.census.gov/geographies/mapping-files/2024/geo/carto-boundary-file.html)",
  "- [Louisiana places ZIP](https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_22_place_500k.zip)",
  "- [Louisiana tracts ZIP](https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_22_tract_500k.zip)",
  "- [Louisiana block groups ZIP](https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_22_bg_500k.zip)", "",
  "Prepared with AI assistance; see [AI usage and actual prompts](../AI_USAGE.md).")
writeLines(doc,"reports/homework6.md")
writeLines(capture.output(sessionInfo()),"tables/homework6_session_info.txt")
print(comparison)
cat("Selected restaurants:",nrow(selected),"Reviews:",nrow(cr),"Place mismatches:",nrow(mismatch),"\n")
