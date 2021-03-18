# check_siege

[Siege](https://github.com/JoeDog/siege) regression test and benchmark utility
adapter for Nagios.


## Requirements

siege, bash


## Usage example

```
$ ./check_siege.sh  -- -c 1 -r 1 www.google.pl
OK: 3 transactions with no alerts. | 'Transactions'=3hits 'Availability'=100.00%;100:;1: 'Elapsed time'=0.30s 'Data transferred'=0.02MB 'Response time'=0.10s 'Transaction rate'=10.00trans/s 'Throughput'=0.07MB/s 'Concurrency'=1.00 'Successful transactions'=3;3:;1:;0;3 'Failed transactions'=0;0;2;0;3 'Longest transaction'=0.17s 'Shortest transaction'=0.06s

$ ./check_siege.sh -v -w Long=0.10,rate=10: -c Long=0.30,rate=5: -- -c 1 -r 1 www.google.pl
WARNING: 3 transactions with 0 critical and 2 warning alerts. Warning: Transaction rate, Longest transaction. | 'Transactions'=3hits 'Availability'=100.00%;100:;1: 'Elapsed time'=0.33s 'Data transferred'=0.02MB 'Response time'=0.11s 'Transaction rate'=9.09trans/s;10:;5: 'Throughput'=0.06MB/s 'Concurrency'=1.00 'Successful transactions'=3;3:;1:;0;3 'Failed transactions'=0;0;2;0;3 'Longest transaction'=0.18s;0.10;0.30 'Shortest transaction'=0.07s
```

See more: [`check_siege.sh -h`](check_siege.sh).


## Licence 

MIT License, Copyright (c) 2021 Paweł Suwiński
