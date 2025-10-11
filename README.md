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
│   ├── opt/                 # Additional Flink plugins, with fluss-flink-tiering.jar
│   └── sql/                 # SQL scripts for data generation
├── fluss-iceberg/           # Main Docker Compose setup
│   ├── docker-compose.yml   # Complete infrastructure stack
│   ├── lib/                 # Iceberg jars for S3 required by Fluss
│   └── trino/               # Trino configuration
└── README.md
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- At least 8GB RAM available for containers
- Ports 8081, 8083, 8181, 9000, 9001 available

### Build Required Images

#### 1. Build Custom Flink Image

The Flink image needs to be built with Iceberg dependencies and Fluss connectors:

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

#### 2. Build Fluss Image

Since the Fluss image for `0.8.0` is not published, you need to build it manually:

```bash
# Clone Fluss
git clone https://github.com/apache/fluss

# Build Fluss
cd fluss
mvn clean install -DskipTests

# Copy jars 
rm -rf docker/build-target/ && mkdir docker/build-target/ && cp -r build-target/* docker/build-target

# Build Fluss image
cd docker
docker build -t fluss:fluss:0.8.0 .
```

> **Note:** This step can be skipped once Fluss 0.8.0 is published.

## 🎯 Running the Demo

### Step 1: Start the Infrastructure

Start all containers:
```bash
cd fluss-iceberg
docker-compose up -d
```

Verify all containers are running:
```bash
docker-compose ps
```

**Access the services:**
- **Flink Web UI**: http://localhost:8083
- **MinIO Console**: http://localhost:9001 (admin/password)
- **Iceberg REST API**: http://localhost:8181

### Step 2: Connect to Flink SQL Client

Enter the Flink SQL CLI:
```bash
docker-compose exec jobmanager ./sql-client
```

**Pre-created Data Sources:**
Three temporary tables are pre-created with faker connector for data generation:

```sql
-- View table schemas
SHOW CREATE TABLE source_customer;
SHOW CREATE TABLE source_order;
SHOW CREATE TABLE source_nation;
```

### Step 3: Set Up Fluss Tables

#### 3.1 Create Fluss Catalog
```sql
CREATE CATALOG fluss_catalog WITH (
    'type' = 'fluss',
    'bootstrap.servers' = 'coordinator-server:9123'
);

USE CATALOG fluss_catalog;
```

#### 3.2 Create Base Tables
```sql
-- Orders table with processing time
CREATE TABLE fluss_order (
    `order_key` BIGINT,
    `cust_key` INT NOT NULL,
    `total_price` DECIMAL(15, 2),
    `order_date` DATE,
    `order_priority` STRING,
    `clerk` STRING,
    `ptime` AS PROCTIME()
);

-- Customer reference table
CREATE TABLE fluss_customer (
    `cust_key` INT NOT NULL,
    `name` STRING,
    `phone` STRING,
    `nation_key` INT NOT NULL,
    `acctbal` DECIMAL(15, 2),
    `mktsegment` STRING,
    PRIMARY KEY (`cust_key`) NOT ENFORCED
);

-- Nation reference table
CREATE TABLE fluss_nation (
    `nation_key` INT NOT NULL,
    `name` STRING,
    PRIMARY KEY (`nation_key`) NOT ENFORCED
);
```

#### 3.3 Create Data Lake Enabled Tables
```sql
-- Enriched orders with data lake enabled
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

-- Revenue aggregation with data lake enabled
CREATE TABLE nation_revenue (
    `nation_name` STRING,
    `revenue` DECIMAL(15, 2),
    PRIMARY KEY (`nation_name`) NOT ENFORCED
) WITH (
    'table.datalake.enabled' = 'true',
    'table.datalake.freshness' = '30s'
);
```

### Step 4: Stream Data Processing

#### 4.1 Load Data into Fluss Tables
```sql
-- Load reference data and streaming orders
EXECUTE STATEMENT SET
BEGIN
    INSERT INTO fluss_nation SELECT * FROM `default_catalog`.`default_database`.source_nation;
    INSERT INTO fluss_customer SELECT * FROM `default_catalog`.`default_database`.source_customer;
    INSERT INTO fluss_order SELECT * FROM `default_catalog`.`default_database`.source_order;
END;
```

#### 4.2 Enrich Orders with Customer and Nation Data
```sql
-- Real-time enrichment with temporal joins
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

#### 4.3 Aggregate Revenue by Nation
```sql
-- Real-time revenue aggregation
INSERT INTO nation_revenue
SELECT nation_name, SUM(total_price) as revenue
FROM enriched_orders
GROUP BY nation_name;
```

### Step 5: Enable Data Lake Tiering

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

### Step 6: Real-Time Analytics on Fluss datalake-enabled Tables

#### 6.1 Query via Trino (Iceberg Only)

Since Fluss with tiering data in Fluss into Iceberg, we can use Trino to query the iceberg tiered.

Open a new terminal, navigate to the fluss-iceberg directory, and execute the following command within this directory to enter into trino cli:

```shell
docker-compose exec trino trino
```

Query tiered data in Iceberg:
```sql
-- Switch to Fluss database
USE iceberg.fluss;

-- Top 5 nations by revenue
SELECT nation_name, revenue
FROM nation_revenue
ORDER BY revenue DESC
LIMIT 5;

-- Count records in enriched orders 
SELECT COUNT(1) FROM enriched_orders;
```

#### 6.2 Query via Flink (Union of Fluss + Iceberg)

Return to Flink SQL terminal and run union queries:

```sql
-- Switch to batch mode for better performance
SET 'execution.runtime-mode' = 'batch';
SET 'sql-client.execution.result-mode' = 'tableau';

-- Count all records (Fluss + Iceberg)
SELECT COUNT(1) FROM enriched_orders;
```

> **Note:** Flink results will be higher than Trino because Flink unions data from both Fluss (hot data) and Iceberg (tiered data).

## 🧹 Cleanup

Stop all containers and remove volumes:
```bash
docker-compose down -v
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

