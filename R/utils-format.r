#' Tools for describing matrices
#'
#' @param x Object to show.
#' @param n Number of rows to show. If `NULL`, the default, will print
#'   all rows if less than option `tibble.print_max`. Otherwise, will
#'   print `tibble.print_min` rows.
#' @param width Width of text output to generate. This defaults to NULL, which
#'   means use `getOption("tibble.width")` or (if also NULL)
#'   `getOption("width")`; the latter displays only the columns that
#'   fit on one screen. You can also set `options(tibble.width = Inf)` to
#'   override this default and always print all columns.
#' @param n_extra Number of extra columns to print abbreviated information for,
#'   if the width is too small for the entire tibble. If `NULL`, the
#'   default, will print information about at most `tibble.max_extra_cols`
#'   extra columns.
#' @seealso \link{tibble-package}
#' @keywords internal
#' @examples
#' trunc_mat(mtcars)
#'
#' print(as_tibble(mtcars))
#' print(as_tibble(mtcars), n = 1)
#' print(as_tibble(mtcars), n = 3)
#' print(as_tibble(mtcars), n = 100)
#'
#' if (!requireNamespace("nycflights13", quietly = TRUE))
#'   stop("Please install the nycflights13 package to run the rest of this example")
#'
#' print(nycflights13::flights, n_extra = 2)
#' print(nycflights13::flights, width = Inf)
#' @name formatting
NULL

#' @export
#' @rdname formatting
#' @importFrom stats setNames
trunc_mat <- function(x, n = NULL, width = NULL, n_extra = NULL) {
  rows <- nrow(x)

  if (is_null(n)) {
    if (is.na(rows) || rows > tibble_opt("print_max")) {
      n <- tibble_opt("print_min")
    } else {
      n <- rows
    }
  }
  n_extra <- n_extra %||% tibble_opt("max_extra_cols")

  df <- as.data.frame(head(x, n))
  width <- tibble_width(width)

  shrunk <- shrink_mat(df, width, rows, n, star = has_rownames(x))
  trunc_info <- list(
    width = width, rows_total = rows, rows_min = nrow(df),
    n_extra = n_extra, summary = tbl_sum(x)
  )

  structure(
    c(shrunk, trunc_info),
    class = c(paste0("trunc_mat_", class(x)), "trunc_mat")
  )
}

#' @importFrom stats setNames
shrink_mat <- function(df, width, rows, n, star) {
  var_types <- map_chr(df, type_sum)

  if (ncol(df) == 0 || nrow(df) == 0) {
    return(new_shrunk_mat(NULL, var_types))
  }

  df <- remove_rownames(df)
  col_names <- tickit(colnames(df))
  names(var_types) <- col_names

  # Minimum width of each column is 5 "<int>", so we can make a quick first
  # pass
  max_cols <- floor(width / 5)
  extra_wide <- (seq_along(df) > max_cols)
  df[] <- df[!extra_wide]

  # List columns need special treatment because format can't be trusted
  classes <- paste0("<", map_chr(df, type_sum), ">")
  is_list <- map_lgl(df, is.list)
  df[is_list] <- map(df[is_list], function(x) {
    summary <- obj_sum(x)
    paste0("<", summary, ">")
  })

  # Character columns need special treatment because of NA
  is_character <- map_lgl(df, is.character)
  df[is_character] <- map(df[is_character], format_character)

  mat <- format(df, justify = "left")
  values <- c(format(rownames(mat))[[1]], unlist(mat[1, ]))
  names <- c("", col_names)

  # Column needs to be as wide as widest of name, values, and class
  w <- pmax(
    pmax(
      nchar_width(encodeString(values)),
      nchar_width(encodeString(names))
    ),
    nchar_width(encodeString(c("", classes)))
  )
  cumw <- cumsum(w + 1)

  too_wide <- cumw[-1] > width
  # Always display at least one column
  if (all(too_wide)) {
    too_wide[1] <- FALSE
    df[[1]] <- substr(df[[1]], 1, width)
  }
  shrunk <- format(df[, !too_wide, drop = FALSE])

  shrunk <- rbind(" " = classes, shrunk)
  if (star)
    rownames(shrunk)[[1]] <- "*"
  colnames(shrunk) <- col_names[!too_wide]

  if (is.na(rows))
    needs_dots <- (nrow(df) >= n)
  else
    needs_dots <- (rows > n)

  if (needs_dots) {
    rows_missing <- rows - n
  } else {
    rows_missing <- 0L
  }

  extra_wide[seq_along(too_wide)] <- too_wide
  new_shrunk_mat(shrunk, var_types[extra_wide], rows_missing)
}

new_shrunk_mat <- function(table, extra, rows_missing = NULL) {
  list(table = table, extra = extra, rows_missing = rows_missing)
}

#' @export
format.trunc_mat <- function(x, ...) {
  c(
    format_comment(format_header(x), width = x$width),
    format_body(x),
    format_comment(pre_dots(format_footer(x)), width = x$width)
  )
}

#' @export
print.trunc_mat <- function(x, ...) {
  cat_line(format(x, ...))
  invisible(x)
}

format_header <- function(x) {
  x$summary
}

format_body <- function(x) {
  table <- x$table
  if (is_null(table)) return()

  table_with_row_names <- c(list(row.names(table)), table)
  table_with_names <- map2(as.list(names(table_with_row_names)), table_with_row_names, c)
  same_width_table <- map(table_with_names, justify_right)
  rows <- invoke(paste, same_width_table)
  rows
}

format_footer <- function(x) {
  extra_rows <- format_footer_rows(x)
  extra_cols <- format_footer_cols(x)

  extra <- c(extra_rows, extra_cols)
  if (length(extra) >= 1) {
    extra[[1]] <- paste0("with ", extra[[1]])
    extra[-1] <- map_chr(extra[-1], function(ex) paste0("and ", ex))
    collapse(extra)
  } else {
    character()
  }
}

format_footer_rows <- function(x) {
  if (!is_null(x$table)) {
    if (is.na(x$rows_missing)) {
      "more rows"
    } else if (x$rows_missing > 0) {
      paste0(big_mark(x$rows_missing), " more rows")
    }
  } else if (is.na(x$rows_total) && x$rows_min > 0) {
    paste0("at least ", x$rows_min, " rows total")
  }
}

format_footer_cols <- function(x) {
  if (length(x$extra) > 0) {
    var_types <- paste0(names(x$extra), NBSP, "<", x$extra, ">")
    if (x$n_extra > 0) {
      if (x$n_extra < length(var_types)) {
        var_types <- c(var_types[seq_len(x$n_extra)], "...")
      }
      vars <- paste0(": ", collapse(var_types))
    } else {
      vars <- ""
    }
    paste0(length(x$extra), " ",
           if (!identical(x$rows_total, 0L) && x$rows_min > 0) "more ",
           "variables", vars)
  }
}

format_comment <- function(x, width) {
  if (length(x) == 0L) return(character())
  map_chr(x, wrap, prefix = "# ", width = min(width, getOption("width")))
}

pre_dots <- function(x) {
  if (length(x) > 0) {
    paste0("... ", x)
  } else {
    character()
  }
}

justify_right <- function(x) {
  width <- nchar_width(x)
  max_width <- max(width)
  spaces_template <- paste(rep(" ", max_width), collapse = "")
  spaces <- map_chr(max_width - width, substr, x = spaces_template, start = 1L)
  paste0(spaces, x)
}

#' knit_print method for trunc mat
#' @keywords internal
#' @export
knit_print.trunc_mat <- function(x, options) {
  summary <- format_header(x)

  kable <- knitr::kable(x$table, row.names = FALSE)

  extra <- format_footer(x)

  if (length(extra) > 0) {
    extra <- wrap("(", collapse(extra), ")", width = x$width)
  } else {
    extra <- "\n"
  }

  res <- paste(c('', '', summary, '', kable, '', extra), collapse = '\n')
  knitr::asis_output(res, cacheable = TRUE)
}

NBSP <- "\U00A0"

wrap <- function(..., indent = 0, prefix = "", width) {
  x <- paste0(..., collapse = "")
  wrapped <- strwrap(x, indent = indent, exdent = indent + 2,
    width = max(width - nchar_width(prefix), 0))
  wrapped <- paste0(prefix, wrapped)
  wrapped <- gsub(NBSP, " ", wrapped)

  paste0(wrapped, collapse = "\n")
}



format_character <- function(x) {
  x[is.na(x)] <- "<NA>"
  x
}

# function for the thousand separator,
# returns "," unless it's used for the decimal point, in which case returns "."
big_mark <- function(x, ...) {
  mark <- if (identical(getOption("OutDec"), ",")) "." else ","
  formatC(x, big.mark = mark, ...)
}

tibble_width <- function(width) {
  if (!is_null(width))
    return(width)

  width <- tibble_opt("width")
  if (!is_null(width))
    return(width)

  getOption("width")
}

tibble_glimpse_width <- function(width) {
  if (!is_null(width))
    return(width)

  width <- tibble_opt("width")
  if (!is_null(width) && is.finite(width))
    return(width)

  getOption("width")
}

pluralise_msg <- function(message, objects) {
  paste0(pluralise(message, objects), format_n(objects))
}

pluralise <- function(message, objects) {
  stopifnot(length(objects) > 0)
  if (length(objects) == 1) {
    # strip [, unless there is space in between
    message <- gsub("\\[(\\S+)\\]", "\\1", message, perl = TRUE)
    # remove ( and its content, unless there is space in between
    message <- gsub("\\([^\\) ]+\\)", "", message, perl = TRUE)
  } else {
    # strip (, unless there is space in between
    message <- gsub("\\((\\S+)\\)", "\\1", message, perl = TRUE)
    # remove [ and its content, unless there is space in between
    message <- gsub("\\[[^\\] ]+\\]\\s+", "", message, perl = TRUE)
  }

  message
}

mult_sign <- function() {
  # unicode multiplication sign
  mult <- "\u00d7"
  # if unicode doesn't render, use lowercase x
  if (enc2native(mult) != mult) {
    mult <- "x"
  }

  mult
}

spaces_around <- function(x) {
  paste0(" ", x, " ")
}

format_n <- function(x) collapse(quote_n(x))

quote_n <- function(x) UseMethod("quote_n")
#' @export
quote_n.default <- function(x) as.character(x)
#' @export
quote_n.character <- function(x) encodeString(x, quote = "'")

collapse <- function(x) paste(x, collapse = ", ")
