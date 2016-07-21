CREATE KEYSPACE test WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '1'}  AND durable_writes = true;

CREATE TABLE test.school (
    student_id text PRIMARY KEY,
    age int,
    major text,
    name text
);

insert into test.school ( student_id, age, name ) values('A889018', 20, 'Fred');
insert into test.school ( student_id, age, name ) values('A373564', 31, 'Kitsune');
insert into test.school ( student_id, age, name ) values('A001390', 24, 'Bob');
insert into test.school ( student_id, age, name ) values('A315848', 28, 'Mike');
insert into test.school ( student_id, age, name ) values('A222803', 25, 'Alex');
insert into test.school ( student_id, age, name ) values('A221881', 12, 'Bartholemew');
insert into test.school ( student_id, age, name ) values('A584658', 30, 'Martha');
insert into test.school ( student_id, age, name ) values('A978039',  7, 'Judy');
insert into test.school ( student_id, age, name, major ) values('A542492', 29, 'Dan', 'Reeling');
insert into test.school ( student_id, age, name, major ) values('A368556', 20, 'Douglas', 'Writhing');
insert into test.school ( student_id, age, name, major ) values('A102655', 28, 'Cassandra', 'Fainting in Coils');

