#' @include dbi-classes.R
NULL

# Drivers ----------------------------------------------------------------

#' @param  dbObj a \code{\linkS4class{SQLServerDriver}} object
#' @param ... Other arguments to methods.
#' @rdname SQLServerDriver-class
#' @export

setMethod(f = 'dbGetInfo', signature = 'SQLServerDriver',
  definition = function (dbObj, ...) {
    list(name = 'RSQLServer (jTDS)',
      driver.version = rJava::.jcall(dbObj@jdrv, "S", "getVersion"))
  }
)

#' @param  object a \code{\linkS4class{SQLServerDriver}} object
#' @rdname SQLServerDriver-class
#' @export

setMethod(f = "show", signature = "SQLServerDriver",
  definition = function (object) {
    cat("<SQLServerDriver>\n")
  }
)

#' Connect to/disconnect from a SQL Server database.
#'
#' @param drv An objected of class \code{\linkS4class{SQLServerDriver}}, or an
#' existing \code{\linkS4class{SQLServerConnection}}. If a connection,
#' the connection will be cloned.
#' @template sqlserver-parameters
#' @return a \code{\linkS4class{SQLServerConnection}}
#' @examples
#' # View sql.yaml file bundled in package
#' file <- system.file("extdata", "sql.yaml", package = "RSQLServer")
#' readLines(file)
#' # Connect using ~/sql.yaml file
#' if (have_test_server()) {
#'  dbConnect(RSQLServer::SQLServer(), "TEST")
#' }
#' # Don't use file argument:
#' \dontrun{
#' dbConnect(RSQLServer::SQLServer(), server="11.1.111.11", port=1434,
#'    properties=list(useNTLMv2="true", domain="myco", user="me",
#'      password="asecret"))
#' }
#' @rdname SQLServer
#' @export

setMethod(f = 'dbConnect', signature = "SQLServerDriver",
  definition = function (drv, server, file = NULL, database = "",
    type = "sqlserver", port = "", properties = list()) {
    # Use sql.yaml file if file is not missing. Note this will then ignore
    # the paramaters type, port and connection properties will be ignored and the
    # information in sql.yaml will be used instead
    sd <- get_server_details(server, file)
    if (!identical(sd, list())) {
      # Server details must include type and port otherwise get_server_file
      # fails
      server <- sd$server
      sd$server <- NULL
      type <- sd$type
      sd$type <- NULL
      port <- sd$port
      sd$port <- NULL
      properties <- sd
    }
    url <- jtds_url(server, type, port, database, properties)
    properties <- rJava::.jnew('java/util/Properties')
    jc <- rJava::.jcall(drv@jdrv, "Ljava/sql/Connection;", "connect", url,
      properties)
    new("SQLServerConnection", jc = jc, identifier.quote = drv@identifier.quote)
  }
)

# DBI methods inherited from DBI
# dbDriver()
#
# DBI methods inherited from RJDBC
# dbUnloadDriver()


# Connections ------------------------------------------------------------

#' @rdname SQLServerConnection-class
#' @export

setMethod(f = 'dbGetInfo', signature = 'SQLServerConnection',
  definition = function (dbObj, ...) {
    meta <- rJava::.jcall(dbObj@jc, "Ljava/sql/DatabaseMetaData;",
      "getMetaData")
    list(db.product.name = rJava::.jcall(meta, "S", "getDatabaseProductName"),
      db.version = rJava::.jcall(meta, "I", "getDatabaseMajorVersion"),
      user = rJava::.jcall(meta, "S","getUserName"))
  }
)

#' @param  object a \code{\linkS4class{SQLServerConnection}} object
#' @rdname SQLServerConnection-class
#' @export

setMethod(f = "show", signature = "SQLServerConnection",
  definition = function (object) {
    info <- dbGetInfo(object)
    cat("<SQLServerConnection>\n")
    cat(info$db.product.name, " v.", info$db.version, "\n", sep = "")
    if (!dbIsValid(object)) {
      cat("  DISCONNECTED\n")
    }
  }
)

#' @rdname SQLServerConnection-class
#' @export

setMethod(f = 'dbIsValid', signature = 'SQLServerConnection',
  definition = function (dbObj, ...) {
    !rJava::.jcall(dbObj@jc, "Z", "isClosed")
  }
)

#' Send query to SQL Server
#'
#' This is basically a copy of RJDBC's \code{\link[RJDBC:JDBCConnection-methods]{dbSendQuery}}
#' method for JDBCConnection, except that this returns a
#' \code{\linkS4class{SQLServerResult}} rather than a JDBCResult.
#'
#' @param statement SQL statement to execute
#' @param ... additional arguments to prepared statement substituted for "?"
#' @param list undocumented
#' @return a \code{\linkS4class{SQLServerResult}} object
#' @rdname SQLServerConnection-class
#' @export

setMethod("dbSendQuery",
  signature(conn = "SQLServerConnection", statement = "character"),
  def = function (conn, statement, ..., list=NULL) {
    statement <- as.character(statement)[1L]
    ## if the statement starts with {call or {?= call then we use CallableStatement
    if (isTRUE(as.logical(grepl("^\\{(call|\\?= *call)", statement)))) {
      s <- rJava::.jcall(conn@jc, "Ljava/sql/CallableStatement;", "prepareCall",
        statement, check=FALSE)
      RJDBC:::.verify.JDBC.result(s,
        "Unable to execute JDBC callable statement ", statement)
      if (length(list(...)))
        RJDBC:::.fillStatementParameters(s, list(...))
      if (!is.null(list))
        RJDBC:::.fillStatementParameters(s, list)
      r <- rJava::.jcall(s, "Ljava/sql/ResultSet;", "executeQuery", check=FALSE)
      RJDBC:::.verify.JDBC.result(r,
        "Unable to retrieve JDBC result set for ", statement)
    } else if (length(list(...)) || length(list)) {
      ## use prepared statements if there are additional arguments
      s <- rJava::.jcall(conn@jc, "Ljava/sql/PreparedStatement;",
        "prepareStatement", statement, check=FALSE)
      RJDBC:::.verify.JDBC.result(s,
        "Unable to execute JDBC prepared statement ", statement)
      if (length(list(...)))
        RJDBC:::.fillStatementParameters(s, list(...))
      if (!is.null(list))
        RJDBC:::.fillStatementParameters(s, list)
      r <- rJava::.jcall(s, "Ljava/sql/ResultSet;", "executeQuery", check=FALSE)
      RJDBC:::.verify.JDBC.result(r,
        "Unable to retrieve JDBC result set for ", statement)
    } else {
      ## otherwise use a simple statement some DBs fail with the above)
      s <- rJava::.jcall(conn@jc, "Ljava/sql/Statement;", "createStatement")
      RJDBC:::.verify.JDBC.result(s,
        "Unable to create simple JDBC statement ", statement)
      r <- rJava::.jcall(s, "Ljava/sql/ResultSet;", "executeQuery",
        as.character(statement)[1], check=FALSE)
      RJDBC:::.verify.JDBC.result(r,
        "Unable to retrieve JDBC result set for ", statement)
    }
    md <- rJava::.jcall(r, "Ljava/sql/ResultSetMetaData;", "getMetaData",
      check=FALSE)
    RJDBC:::.verify.JDBC.result(md,
      "Unable to retrieve JDBC result set meta data for ", statement,
      " in dbSendQuery")
    new("SQLServerResult", jr=r, md=md, stat=s, pull=rJava::.jnull())
  }
)

#' @rdname SQLServerConnection-class
#' @export
setMethod(f = "dbBegin", signature = "SQLServerConnection",
  # Will be called by dplyr::db_begin.DBIConnection
  definition = function (conn, ...) {
    # https://technet.microsoft.com/en-us/library/aa225983(v=sql.80).aspx
    # https://msdn.microsoft.com/en-us/library/ms188929.aspx
    dbGetQuery(conn, "BEGIN TRANSACTION")
  }
)

#' @param obj An R object whose SQL type we want to determine
#' @rdname SQLServerConnection-class
#' @export
setMethod(f = "dbDataType", signature = c("SQLServerConnection", "ANY"),
  def = function (dbObj, obj, ...) {
    # RJDBC method is too crude. See:
    # https://github.com/s-u/RJDBC/blob/1b7ccd4677ea49a93d909d476acf34330275b9ad/R/class.R
    # Based on db_data_type.MySQLConnection from dplyr
    # https://msdn.microsoft.com/en-us/library/ms187752(v=sql.90).aspx
    char_type <- function (x) {
      n <- max(nchar(as.character(x)))
      if (n <= 8000) {
        paste0("varchar(", n, ")")
      } else {
        "text"
      }
    }
    switch(class(obj)[1],
      logical = "bit",
      integer = "int",
      numeric = "float",
      factor =  char_type(obj),
      character = char_type(obj),
      # SQL Server does not have a date data type without time corresponding
      # to R's Date class
      Date = "datetime",
      POSIXct = "datetime",
      stop("Unknown class ", paste(class(obj), collapse = "/"), call. = FALSE)
    )
  }
)

# DBI methods that inherit from RJDBC:
# dbDisconnect()
# dbGetQuery()
# dbGetException()
# dbListResults()
# dbListFields()
# dbListTables()
# dbReadTable()
# dbWriteTable()
# dbExistsTable()
# dbRemoveTable()
# dbCommit()
# dbRollback()

# Results ----------------------------------------------------------------

#' @param dbObj An object inheriting from \code{\linkS4class{SQLServerResult}}
#' @rdname SQLServerResult-class
#' @export
setMethod (f = 'dbIsValid', signature = 'SQLServerResult',
  definition = function (dbObj) {
    rJava::.jcall(dbObj@jr, "Z", "isClosed")
  }
)

# Per DBI documentation:
# "fetch is provided for compatibility with older DBI clients - for all new
# code you are strongly encouraged to use dbFetch."
# RJDBC does not currently have a dbFetch method.

#' @param res an object inheriting from \code{\linkS4class{SQLServerResult}}
#' @param n  If n is -1 then the current implementation fetches 32k rows first
#' and then (if not sufficient) continues with chunks of 512k rows, appending
#' them. If the size of the result set is known in advance, it is most efficient
#' to set n to that size.
#' @param ... other arguments passed to method
#' @rdname SQLServerResult-class
#' @export
setMethod("dbFetch", "SQLServerResult", function (res, n = -1, ...) {
  RJDBC::fetch(res, n)
})

#' @rdname SQLServerResult-class
#' @export
setMethod(f = "dbGetInfo", signature = "SQLServerResult",
  def = function (dbObj, ...) {
    list(statement = dbObj@stat,
      row.count = rJava::.jcall(dbObj@res, "I", "getRow"),
      rows.affected = rJava::.jcall(dbObj@res, "I", "getFetchSize"),
      has.completed = rJava::.jcall(dbObj@res, "Z", "isClosed"),
      # No JDBC method is available that determines whether statement is a
      # SELECT
      is.select = NA)
  }
)

#' @rdname SQLServerResult-class
#' @export
setMethod("dbColumnInfo", "SQLServerResult", def = function (res, ...) {
  # Inspired by RJDBC method for JDBCResult
  # https://github.com/s-u/RJDBC/blob/1b7ccd4677ea49a93d909d476acf34330275b9ad/R/class.R
  cols <- rJava::.jcall(res@md, "I", "getColumnCount")
  df <- dplyr::data_frame(field.name = character(),
    field.type = character(),
    data.type = character())
  if (cols < 1) return(df)
  for (i in 1:cols) {
    df$field.name[i] <- rJava::.jcall(res@md, "S", "getColumnName", i)
    df$field.type[i] <- rJava::.jcall(res@md, "S", "getColumnTypeName", i)
    ct <- rJava::.jcall(res@md, "I", "getColumnType", i)
    df$data.type[i] <- jdbcToRType(ct)
  }
  df
})

#' @rdname SQLServerResult-class
#' @export
setMethod("dbHasCompleted", "SQLServerResult", def = function (res, ...) {
  # Need to override RJDBC method as it always returns TRUE
  dbGetInfo(res)$has.completed
})


# Inherited from DBI:
# show()
# dbFetch()
# dbGetStatement()
# dbGetRowsAffected()
# dbGetRowCount()
#
# Inherited from RJDBC:
# fetch()
# dbClearResult()
# dbGetInfo()

