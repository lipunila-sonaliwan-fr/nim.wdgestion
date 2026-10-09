procedure TEST
  sql "create table a (x integer); insert into a values (10)"
  utiliser a
  x = 5
  ? x, m->x
retourner
