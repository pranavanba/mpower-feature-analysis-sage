#' Utility feature extraction function to
#' map based on file column name and recordId
#' (inherited from get_table())
#' 
#' @param data
#' @return dataframe/tibble tapping features
map_feature_extraction <- function(data, 
                                   file_parser, 
                                   feature_funs,
                                   ...){
    features <- furrr::future_pmap_dfr(
        list(recordId = data$recordId,
             fileColumnName = data$fileColumnName,
             filePath = data$filePath), 
        file_parser = file_parser,
        feature_funs = feature_funs,
        function(recordId,
                 fileColumnName, 
                 filePath, 
                 file_parser, 
                 feature_funs){
            file_parser <- partial(file_parser)
            feature_funs <- partial(feature_funs, ...)
            filePath %>%
                file_parser() %>%
                feature_funs() %>%
                dplyr::mutate(
                    recordId = recordId,
                    fileColumnName = fileColumnName) %>%
                dplyr::select(recordId, 
                              fileColumnName, 
                              everything())})
    data %>%
        dplyr::select(
            all_of(c("recordId", 
                     "fileColumnName"))) %>%
        dplyr::left_join(
            features, by = c("recordId", "fileColumnName"))
}

get_github_url <- function(git_token_path, 
                           git_repo,
                           script_path,
                           ...){
    setGithubToken(readLines(git_token_path))
    githubr::getPermlink(
        git_repo, 
        repositoryPath = script_path,
        ...)
}

save_to_synapse <- function(data, 
                            output_filename, 
                            parent,
                            ...){
    data %>% 
        readr::write_tsv(output_filename)
    file <- File(output_filename, parent =  parent)
    activity <- Activity(...)
    synStore(file, activity = activity)
    unlink(file$path)
}

#' function to get synapse table in reticulate
#' into tidy-format (pivot based on filecolumns if exist)
#' @param synapse_tbl tbl id in synapse
#' @param file_columns file_columns to download
get_table <- function(synapse_tbl, 
                      file_columns = NULL,
                      query_params = NULL){
    # get table entity
    if(is.null(query_params)){
        entity <- synTableQuery(glue::glue("SELECT * FROM {synapse_tbl}"))
    }else{
        entity <- synTableQuery(glue::glue("SELECT * FROM {synapse_tbl} {query_params}"))
    }
    
    # shape table
    table <- entity$asDataFrame() %>%
        tibble::as_tibble(.)
    
    # download all table columns
    if(!is.null(file_columns)){
        table <-  table %>%
            tidyr::pivot_longer(
                cols = all_of(file_columns), 
                names_to = "fileColumnName", 
                values_to = "fileHandleId") %>%
            dplyr::mutate(across(everything(), unlist)) %>%
            dplyr::mutate(fileHandleId = as.character(fileHandleId)) %>%
            dplyr::filter(!is.na(fileHandleId)) %>%
            dplyr::group_by(recordId, fileColumnName) %>% 
            dplyr::summarise_all(last) %>% 
            dplyr::ungroup()
        result <- synDownloadTableColumns(
            table = entity, 
            columns = file_columns) %>%
            tibble::enframe(.) %>%
            tidyr::unnest(value) %>%
            dplyr::select(
                fileHandleId = name, 
                filePath = value) %>%
            dplyr::mutate(filePath = unlist(filePath)) %>%
            dplyr::right_join(table, by = c("fileHandleId"))
    }else{
        result <- table
    }
    return(result)
}

normalize_timestamp <- function(data){
    if(median(data$t) > 1000){
        data <- data %>% 
            dplyr::mutate(t = t/1000)
    }
    return(data %>%
               dplyr::arrange(t))
}


curate_app_version <- function(data){
    data %>% 
        tidyr::separate(appVersion, 
                        ",", 
                        into = c("version", "build"), 
                        remove = FALSE) %>%
        dplyr::select(-build)
}


curate_med_timepoint <- function(data){
    if("answers.medicationTiming" %in% names(data)){
        data %>% 
            dplyr::select(everything(), 
                          medTimepoint := answers.medicationTiming)
    }else{
        data
    }
}

curate_phone_info <- function(data){
    data %>%
        dplyr::mutate(using_ios_phone = 
                          ifelse(str_detect(phoneInfo, 
                                            "iOS|iPhone"), 
                                 TRUE, FALSE)) %>%
        dplyr::select(-phoneInfo)
    
}

remove_test_user <- function(data){
    test_user <- data %>%
        dplyr::filter(str_detect(dataGroups, "test_user")) 
    data %>% 
        dplyr::anti_join(test_user, by = c("recordId"))
}
