# Fluss Iceberg Demo

A comprehensive demonstration of **Fluss** (a distributed streaming database) integrated with **Apache Iceberg** for data lakehouse capabilities. This repository showcases how to set up and run a complete data streaming pipeline using Fluss, Apache Flink, Apache Iceberg, and supporting infrastructure.

## 🏗️ Architecture

This demo includes a complete data lakehouse stack:

- **Fluss v0.8**: Distributed streaming database with Iceberg integration
- **Apache Flink 1.20**: Stream processing engine
- **Apache Iceberg**: Open table format for data lakehouse
- **Apache Trino**: SQL query engine for analytics on Apache Iceberg
- **MinIO**: S3-compatible object storage

## 📁 Project Structure

```
├── flink/                    # Flink cluster with Iceberg support
│   ├── Dockerfile           # Custom Flink image with Iceberg jars
│   ├── lib/                 # Required JAR files
│   ├── opt/                 # Additional Flink plugins, with fluss-flink-tiering.jar put
│   └── sql/                 # SQL scripts for data generation
├── fluss-iceberg/           # Main Docker Compose setup
│   ├── docker-compose.yml   # Complete infrastructure stack
│   ├── lib/                 # Iceberg jars for S3 required by Fluss to create tables backed on s3
│   └── trino/               # Trino configuration
└── README.md
```

## Prerequisites

#### Build Custom Flink Image

The Flink image needs to be built with Iceberg dependencies and Fluss connectors. This custom image includes:

**Required Dependencies:**
- `fluss-flink-1.19-0.8-SNAPSHOT.jar` - Fluss Flink connector
- `fluss-lake-iceberg-0.8-SNAPSHOT.jar` - Fluss Iceberg integration
- `iceberg-aws-1.10.0.jar` - Iceberg AWS S3 support
- `iceberg-aws-bundle-1.8.1.jar` - Iceberg AWS bundle
- `hadoop-apache-3.3.5-2.jar` - Hadoop dependencies
- `failsafe-3.3.2.jar` - Resilience library
- `flink-faker-0.5.3.jar` - Data generation connector

**Build the Flink image:**
```bash
cd flink
docker build -t fluss-flink-iceberg:1.20-0.8.0 .
```

**What this image includes:**
- Base Flink 1.20.0 with Scala 2.12 and Java 17
- All Iceberg and AWS S3 dependencies
- Fluss Flink connector for streaming database integration
- Flink Faker connector for data generation
- Pre-configured SQL client with demo scripts
- Fluss tiering plugin jar to tier to iceberg

#### Build Fluss Image
Since the Fluss image for `0.8.0` is not published, you will need to build Fluss `0.8.0` manually. Following the steps to build Fluss `0.8.0` image:
```shell
# Clone Fluss
git clone https://github.com/apache/fluss

# Build Fluss
cd fluss
mvn clean install -DskipTests

# Copy jars 
rm -rf docker/build-target/ && mkdir docker/build-target/ && cp -r  build-target/* docker/build-target

# Build Fluss image
cd docker
docker build -t fluss:fluss:0.8.0 .
```

Note: This step can be skipped once Fluss 0.8.0 is published.

## Running the Demo

### Start required components

#### Start all containers
To start all containers, run:
```bash
cd fluss-iceberg
docker-compose up -d
```

This command automatically starts all the containers defined in the Docker Compose configuration in detached mode.
Run
```shell
docker container ls -a
```
to check whether all containers are running properly.

#### Access the services:
- **Flink Web UI**: http://localhost:8083
- **MinIO Console**: http://localhost:9001 (admin/password)
- **Iceberg REST API**: http://localhost:8181 


### Enter into SQL-Client
First, use the following command to enter the Flink SQL CLI Container:
```shell
docker-compose exec jobmanager ./sql-client
```

Note: To simplify this guide, three temporary tables have been pre-created with faker connector to generate data. You can view their schemas by running the following commands:

```shell
SHOW CREATE TABLE source_customer;
```

```shell
SHOW CREATE TABLE source_order;
```

```shell
SHOW CREATE TABLE source_nation;
```

### Create Fluss Tables

#### Create Fluss Catalog
Use the following SQL to create a Fluss catalog:
```sql
CREATE CATALOG fluss_catalog WITH (
    'type' = 'fluss',
    'bootstrap.servers' = 'coordinator-server:9123'
);
```

```sql
USE CATALOG fluss_catalog;
```

#### Create Tables
Running the following SQL to create Fluss tables to be used in this guide:
```sql
CREATE TABLE fluss_order (
    `order_key` BIGINT,
    `cust_key` INT NOT NULL,
    `total_price` DECIMAL(15, 2),
    `order_date` DATE,
    `order_priority` STRING,
    `clerk` STRING,
    `ptime` AS PROCTIME()
);
```

```sql
CREATE TABLE fluss_customer (
    `cust_key` INT NOT NULL,
    `name` STRING,
    `phone` STRING,
    `nation_key` INT NOT NULL,
    `acctbal` DECIMAL(15, 2),
    `mktsegment` STRING,
    PRIMARY KEY (`cust_key`) NOT ENFORCED
);
```

```sql
CREATE TABLE fluss_nation (
  `nation_key` INT NOT NULL,
  `name`       STRING,
   PRIMARY KEY (`nation_key`) NOT ENFORCED
);
```

```sql
CREATE TABLE enriched_orders (
    `order_key` BIGINT,
    `cust_key` INT NOT NULL,
    `total_price` DECIMAL(15, 2),
    `order_date` DATE,
    `order_priority` STRING,
    `clerk` STRING,
    `cust_name` STRING,
    `cust_phone` STRING,
    `cust_acctbal` DECIMAL(15, 2),
    `cust_mktsegment` STRING,
    `nation_name` STRING
) WITH (
    'table.datalake.enabled' = 'true',
    'table.datalake.freshness' = '30s'
);
```

```sql
CREATE TABLE nation_revenue (
    `nation_name` STRING,
    `revenue` DECIMAL(15, 2),
     PRIMARY KEY (`nation_name`) NOT ENFORCED
) WITH (
    'table.datalake.enabled' = 'true',
    'table.datalake.freshness' = '30s'
);
```

### Streaming into Fluss
1. Insert into Fluss tables from data gen source table
```sql
EXECUTE STATEMENT SET
BEGIN
    INSERT INTO fluss_nation SELECT * FROM `default_catalog`.`default_database`.source_nation;
    INSERT INTO fluss_customer SELECT * FROM `default_catalog`.`default_database`.source_customer;
    INSERT INTO fluss_order SELECT * FROM `default_catalog`.`default_database`.source_order;
END;
```

2. Enrich `fluss_order` table with `fluss_nation`, `fluss_customer` tables to `enriched_orders` table
```sql
-- insert tuples into enriched_orders
INSERT INTO enriched_orders
SELECT o.order_key,
       o.cust_key,
       o.total_price,
       o.order_date,
       o.order_priority,
       o.clerk,
       c.name,
       c.phone,
       c.acctbal,
       c.mktsegment,
       n.name
FROM fluss_order o
       LEFT JOIN fluss_customer FOR SYSTEM_TIME AS OF `o`.`ptime` AS `c`
                 ON o.cust_key = c.cust_key
       LEFT JOIN fluss_nation FOR SYSTEM_TIME AS OF `o`.`ptime` AS `n`
                 ON c.nation_key = n.nation_key;
```

3. Average `enriched_orders` to calculate revenue by nation
```sql
INSERT INTO nation_revenue
  SELECT nation_name, sum(total_price) as revenue
  FROM enriched_orders
  GROUP BY nation_name;
```

### Start Lakehouse Tiering Service

Open a new terminal, navigate to the fluss-iceberg directory, and execute the following command within this directory to start the lake tiering service:
```sql
docker-compose exec jobmanager \
    /opt/flink/bin/flink run \
    /opt/flink/opt/fluss-flink-tiering-0.8-SNAPSHOT.jar \
    --fluss.bootstrap.servers coordinator-server:9123 \
    --datalake.format iceberg \
    --datalake.iceberg.type rest \
    --datalake.iceberg.warehouse s3://warehouse/ \
    --datalake.iceberg.uri http://rest:8181 \
    --datalake.iceberg.io-impl org.apache.iceberg.aws.s3.S3FileIO \
    --datalake.iceberg.s3.endpoint http://minio:9000 \
    --datalake.iceberg.s3.path-style-access true
```

### Real-Time Analytics on Fluss datalake-enabled Tables

#### Query on Iceberg via Trino

Since Fluss with tiering data in Fluss into Iceberg, we can use Trino to query the iceberg tiered.

##### Enter into Trino CLI
Open a new terminal, navigate to the fluss-iceberg directory, and execute the following command within this directory to enter into trino cli:

```shell
docker-compose exec trino trino
```

##### Run queries via Trino
Switch into fluss db:
```sql
use iceberg.fluss;
```

Run query on `nation_revenue` table to see the Top5 revenue by nation
```sql
SELECT nation_name, revenue
FROM nation_revenue
ORDER BY revenue DESC
LIMIT 5;
```

Run query on `enriched_orders` table to see how many rows already in the iceberg table
```sql
SELECT COUNT(1) FROM enriched_orders
```

#### Union Read Fluss and Iceberg via Flink
Back to Flink SQL terminal to run queries to union read data in Fluss and Iceberg:
```sql
-- switch to batch mode
SET 'execution.runtime-mode' = 'batch';
```
```sql
-- use tableau result mode
SET 'sql-client.execution.result-mode' = 'tableau';
```

Run the SQL to see how many rows
```sql
SELECT COUNT(1) FROM enriched_orders
```
Run it multiple times, should be different every time.
Go to Trino terminal to run same query. The result in Flink should be more than 
in Trino since Flink will union the datasets that already in Iceberg and still in Fluss.


### Clean up
After finishing the tutorial, run exit to exit Flink SQL CLI Container and then run
```shell
docker compose down -v
```
to stop all containers.

