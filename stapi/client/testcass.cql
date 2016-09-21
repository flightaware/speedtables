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

create index school_name_index on test.school(name);

CREATE TABLE test.class (
	room text,
	hour int,
	subject text,
	PRIMARY KEY (room, hour)
);

insert into test.class ( room, hour, subject ) values( '1301', 8, 'Uglification' );
insert into test.class ( room, hour, subject ) values( '1302', 8, 'Derision' );
insert into test.class ( room, hour, subject ) values( '1303', 8, 'Fainting' );
insert into test.class ( room, hour, subject ) values( '1301', 10, 'Reeling' );
insert into test.class ( room, hour, subject ) values( '1302', 10, 'Writhing' );
insert into test.class ( room, hour, subject ) values( '1303', 10, 'Fainting' );
insert into test.class ( room, hour, subject ) values( '1301', 13, 'Uglification II' );
insert into test.class ( room, hour, subject ) values( '1302', 13, 'Confusion' );
insert into test.class ( room, hour, subject ) values( '1303', 13, 'Derision II' );
insert into test.class ( room, hour, subject ) values( '1301', 15, 'Band' );
insert into test.class ( room, hour, subject ) values( '1302', 15, 'Shop' );
insert into test.class ( room, hour, subject ) values( '1303', 15, 'Uglification III' );
