---
layout: post
title: Connecting to Snowflake with Ruby on Rails
source: https://eng.localytics.com/connecting-to-snowflake-with-ruby-on-rails/
---

At [Localytics](https://www.localytics.com/), one of the tools we use for data processing is the [Snowflake](https://www.snowflake.net/) data warehouse. We connect to Snowflake in a couple different ways, but our main data retrieval application is a [Ruby on Rails](http://rubyonrails.org/) API. To accomplish this we use a combination of [unixODBC](http://www.unixodbc.org/) (an open-source implementation of the [ODBC](https://docs.microsoft.com/en-us/sql/odbc/microsoft-open-database-connectivity-odbc) standard), Snowflake's [ODBC driver](https://docs.snowflake.net/manuals/user-guide/odbc.html), and our own [ODBC ActiveRecord adapter](http://eng.localytics.com/odbc-and-writing-your-own-activerecord-adapter/) for Ruby on Rails. This sequence of tools allows us to take full advantage of ActiveRecord's query generation and general ease-of-use while still enjoying all the benefits of a fully cloud-enabled data warehouse such as Snowflake.

## ODBC

First, a bit of background on the ODBC standard. ODBC is a common interface through which you can connect to multiple backend databases in the same manner. In this way it enables users to write code now and maintain the ability to migrate later, while also mitigating the pain of learning each DBMS's idiosyncrasies. You connect to a data store through an ODBC adapter, which implements the ODBC interface for that specific DBMS.

For example, the following code will execute the query `SELECT id, name FROM users` on any database without you needing to make changes to the code, just by passing in a data store name (DSN) as the first command-line argument to this script.

```makefile
run: odbc
  ./odbc $(DSN)

odbc:
  gcc -lodbc odbc.c -o odbc
```

```c
#include <stdio.h>
#include <stdlib.h>
#include <sql.h>
#include <sqlext.h>
#include <string.h>

int main (int argc, char **argv) {
  SQLHENV henv   = SQL_NULL_HENV;  // Environment
  SQLHDBC hdbc   = SQL_NULL_HDBC;  // Connection handle
  SQLHSTMT hstmt = SQL_NULL_HSTMT; // Statement handle

  SQLRETURN retcode;      // Return status of a query
  SQLBIGINT userId;       // holds the ID of the user
  SQLTCHAR userName[256]; // buffer to hold name of the user

  // Establish the connection string
  char connStr[strlen(argv[1]) + 5];
  sprintf(connStr, "DSN=%s;", argv[1]);

  // Allocate and initialize the environment and connection handles
  SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &henv);
  SQLSetEnvAttr(henv, SQL_ATTR_ODBC_VERSION, (SQLPOINTER*)SQL_OV_ODBC3, 0);
  SQLAllocHandle(SQL_HANDLE_DBC, henv, &hdbc);

  // Connect to data source and allocate the statement handle
  SQLDriverConnect(hdbc, NULL, (SQLCHAR *)connStr, SQL_NTS, NULL, 0, NULL, SQL_DRIVER_COMPLETE);
  SQLAllocHandle(SQL_HANDLE_STMT, hdbc, &hstmt);

  // Fetch the results of a query and bind the columns
  SQLExecDirect(hstmt, (SQLCHAR *)"SELECT id, name FROM users", SQL_NTS);
  SQLBindCol(hstmt, 1, SQL_C_SBIGINT, (SQLPOINTER)&userId, sizeof(userId), NULL);
  SQLBindCol(hstmt, 2, SQL_C_TCHAR, (SQLPOINTER)userName, sizeof(userName), NULL);

  // Fetch and print each row of data until SQL_NO_DATA returned.
  while (SQL_SUCCEEDED(retcode = SQLFetchScroll(hstmt, SQL_FETCH_NEXT, 1))) {
    printf("User %ld: %s\n", userId, userName);
  }

  // Free the allocated handles
  if (hstmt != SQL_NULL_HSTMT)
    SQLFreeHandle(SQL_HANDLE_STMT, hstmt);

  if (hdbc != SQL_NULL_HDBC) {
    SQLDisconnect(hdbc);
    SQLFreeHandle(SQL_HANDLE_DBC, hdbc);
  }

  if (henv != SQL_NULL_HENV)
    SQLFreeHandle(SQL_HANDLE_ENV, henv);

  return 0;
}
```

DSNs are a string of key-value pairs representing the connection configuration. They correspond to an entry in an `odbc.ini` file that you configure. You can then reference the configured DSN using an implementation of ODBC (e.g., unixODBC) to connect to an ODBC DBMS like Snowflake. For example, in your `odbc.ini` file you might have:

```ini
[LocalyticsProductionSnowflake]
Driver        = SnowflakeDSIIDriver;
Locale        = en-US;
Server        = yoursnowflakeaccount.snowflakecomputing.com;
Port          = 443;
Account       = yoursnowflakeaccount;
Database      = PRODUCTION;
Schema        = PRODUCTION;
Warehouse     = QUERY_WH;
Role          = QUERY;
SSL           = on;
Query_Timeout = 270;
uid           = ...;
pwd           = ...;
```

The configuration above operates under the assumption that you've previously installed the adapter for each type of DBMS to which you're attempting to connect.

## Installation

Installing `unixODBC` is relatively straightforward on *NIX-based machines (on Windows ODBC actually ships with the OS by default). Run whichever package manager your machine uses (e.g., `brew`, `apt-get`, `yum`, etc.) to install `unixodbc` and `unixodbc-dev` (to get the headers needing for linking). Fortunately Snowflake provides [great documentation](https://docs.snowflake.net/manuals/user-guide/odbc.html) on how to handle the Snowflake-specific steps of getting ODBC set up, so follow those instructions as well.

Once you do, make sure to take full advantage of the `isql` utility that comes with `unixODBC`, as it can be invaluable for debugging. `isql` will drop you into an SQL terminal connected to any given DSN; for example:

```
[17:38:30] ~ $ isql LocalyticsProductionSnowflake
+---------------------------------------+
| Connected!                            |
|                                       |
| sql-statement                         |
| help [tablename]                      |
| quit                                  |
|                                       |
+---------------------------------------+
SQL> SELECT COUNT(*) FROM fact_events WHERE app_name = 'Localytics Test';
+----------+
| COUNT(*) |
+----------+
| 226975   |
+----------+
SQLRowCount returns 1
1 rows fetched
SQL>
```

## odbc_adapter

Once you're comfortably set up with `unixODBC` and Snowflake's adapter, you can configure your Ruby on Rails app to connect to Snowflake like you would any other data store. First, add the `odbc_adapter` gem to your `Gemfile` like so:

```ruby
gem 'odbc_adapter', '~> 5.0.3'
```

Then run `bundle install` to download the gem to your system. (Note that the major and minor version of the gem are linked to the dependent Rails version, so if your app is not yet running Rails `5.0.x`, you'll need to specify `4.2.3` or `3.2.0`). Then, edit your `config/database.yml` to specify the Snowflake connection for a given environment, like so:

```yaml
snowflake:
  adapter: odbc
  dsn: LocalyticsProductionSnowflake
```

This tells Rails to use those connection settings when running in production mode. The final step is to register Snowflake as a valid connection option within the `odbc_adapter` gem. By default, `odbc_adapter` ships with support for `MySQL` and `PostgreSQL`. Fortunately, it also ships with the ability to register you own adapters as well. To accomplish this, add the following code to an initializer, e.g. `config/initializers/odbc.rb`:

```ruby
require 'active_record/connection_adapters/odbc_adapter'
require 'odbc_adapter/adapters/postgresql_odbc_adapter'

ODBCAdapter.register(/snowflake/, ODBCAdapter::Adapters::PostgreSQLODBCAdapter) do
  # Explicitly turning off prepared statements as they are not yet working with
  # snowflake + the ODBC ActiveRecord adapter
  def prepared_statements
    false
  end

  # Quoting needs to be changed for snowflake
  def quote_column_name(name)
    name.to_s
  end

  private

  # Override dbms_type_cast to get the values encoded in UTF-8
  def dbms_type_cast(columns, values)
    values.each do |row|
      row.each_index do |idx|
        row[idx] = row[idx].force_encoding('UTF-8') if row[idx].is_a?(String)
      end
    end
  end
end
```

This code does a couple of things. It tells the `odbc_adapter` gem that if when ODBC reports back the connected DBMS's type it matches the `/snowflake/` regex, to use the subsequent block to create a class to act as the adapter. We're then using the PostgreSQL adapter as the superclass, because the syntax is close enough so as it work. Finally, it handles the Snowflake-specific setup of turning off prepared statements, quoting column names correctly, and forcing strings to come back in UTF-8 encoding.

## ActiveRecord

Once you've configured the `odbc_adapter` gem, you can take advantage of it by connecting your models to that connection. First, create a model that corresponds to a table in your Snowflake schema. For instance, in our production schema we have a table called `fact_events`. Second, call `establish_connection` to tell `ActiveRecord` to connect to the correct database configuration from `database.yml`. For example:

```ruby
class FactEvent < ApplicationRecord
  establish_connection(:snowflake)
end
```

Note that if all of your models are going to be reading and writing from Snowflake for a given environment (development, production, etc.) then you can name the connection after the environment and the `establish_connection` call becomes unnecessary. With these models in place, you can perform any of the [normal `ActiveRecord` queries](http://guides.rubyonrails.org/active_record_basics.html).

## Roadmap / OSS opportunities

This configuration works for us, and we've been happily running this code in production since January of 2017. That being said, there are still a couple of things that we'd like to build into our adapter to make it even better.

### Out-of-the-box Snowflake support

Currently, every project that uses Snowflake needs the initializer mentioned above because the `odbc_adapter` gem doesn't come with Snowflake support baked in. At the moment subclassing the PostgreSQL adapter works for us, but we'd like to fully support Snowflake's driver so that we can take advantage of some of the more advanced UDF capabilities that Snowflake has to offer.

### Rails 5.1

The latest version of Rails was recently released, so in order to upgrade our applications we need to go through and ensure that our adapter works with all of the new capabilities of the latest version of ActiveRecord.

### Prepared statements

Our adapter supports prepared statements for the `PostgreSQL` adapter, but it's explicitly turned off for `MySQL` and `Snowflake`. We'd like to take advantage of caching prepared statements to cut down on memory allocations and generally improve performance by enabling it for these two adapters.

## Wrapping up

Snowflake is a great option for a cloud-based data warehouse, and solved a lot of problems that we've had with previous solutions to the problem of storing massive amounts of data. By being ODBC compliant, it enables us to connect using all of our favorite tools with minimal setup. If you also would like to use Snowflake with Ruby on Rails, feel free to install our `odbc_adapter` gem and give it a shot. When you do please share your experience, approach, and any feedback in a gist, on a blog, or in the comments.
