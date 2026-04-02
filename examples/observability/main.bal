// SQL Connection Pool Observability Example
//
// A REST API backed by PostgreSQL that demonstrates the sql module's built-in
// observability. This service contains no metric instrumentation code — pool
// health and connection event timing are emitted automatically by the sql
// module's HikariCP integration.
//
// Enable observability with two settings:
//   Ballerina.toml:  observabilityIncluded = true
//   Config.toml:     ballerina.observe.metricsEnabled = true

import ballerina/http;
import ballerina/sql;
import ballerinax/postgresql;
import ballerinax/prometheus as _;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
// These values are read from Config.toml at startup. They match the PostgreSQL
// container defined in docker-compose.yml.

configurable string dbHost = ?;
configurable int dbPort = ?;
configurable string dbName = ?;
configurable string dbUser = ?;
configurable string dbPass = ?;

// ---------------------------------------------------------------------------
// Database client
// ---------------------------------------------------------------------------
// `postgresql:Client` manages a HikariCP connection pool internally. Pool
// health metrics (active/idle/total connections, utilization ratio) and
// connection event timing (acquisition, usage, creation) are reported
// automatically when observability is enabled.

final postgresql:Client dbClient = check new (
    host = dbHost, port = dbPort, database = dbName,
    username = dbUser, password = dbPass
);

// ---------------------------------------------------------------------------
// Record types
// ---------------------------------------------------------------------------
// Ballerina uses these record types to map SQL result rows. The field names
// must match the column names (or use @sql:Column to override).

type Student record {|
    int id;
    string first_name;
    string last_name;
    int age;
|};

// Payload for creating a new student (no id — the database generates it).
type NewStudent record {|
    string first_name;
    string last_name;
    int age;
|};

// ---------------------------------------------------------------------------
// HTTP service
// ---------------------------------------------------------------------------
// Each endpoint uses a different sql:Client method. Pool health and connection
// event metrics are reported automatically when observability is enabled.

service /api on new http:Listener(8080) {

    // GET /api/students — fetch all students.
    resource function get students() returns Student[]|http:InternalServerError {
        stream<Student, sql:Error?> studentStream = dbClient->query(
            `SELECT * FROM Students`
        );
        Student[]|sql:Error students = from Student s in studentStream
            select s;

        if students is sql:Error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return students;
    }

    // GET /api/students/{id} — fetch a single student by ID.
    resource function get students/[int id]()
            returns Student|http:NotFound|http:InternalServerError {
        Student|sql:Error student = dbClient->queryRow(
            `SELECT * FROM Students WHERE id = ${id}`
        );

        if student is sql:NoRowsError {
            return http:NOT_FOUND;
        }
        if student is sql:Error {
            return http:INTERNAL_SERVER_ERROR;
        }
        return student;
    }

    // POST /api/students — create a new student.
    resource function post students(@http:Payload NewStudent newStudent)
            returns record {|int id; *NewStudent;|}|http:InternalServerError {
        sql:ExecutionResult|sql:Error result = dbClient->execute(
            `INSERT INTO Students (first_name, last_name, age)
             VALUES (${newStudent.first_name}, ${newStudent.last_name},
                     ${newStudent.age})`
        );

        if result is sql:Error {
            return http:INTERNAL_SERVER_ERROR;
        }

        var lastId = result.lastInsertId;
        int insertedId = 0;
        if lastId is int {
            insertedId = lastId;
        } else if lastId is string {
            int|error parsed = int:fromString(lastId);
            if parsed is int {
                insertedId = parsed;
            }
        }
        return {id: insertedId, ...newStudent};
    }

    // DELETE /api/students/{id} — remove a student by ID.
    resource function delete students/[int id]()
            returns http:Ok|http:NotFound|http:InternalServerError {
        sql:ExecutionResult|sql:Error result = dbClient->execute(
            `DELETE FROM Students WHERE id = ${id}`
        );

        if result is sql:Error {
            return http:INTERNAL_SERVER_ERROR;
        }
        if result.affectedRowCount == 0 {
            return http:NOT_FOUND;
        }
        return http:OK;
    }
}
