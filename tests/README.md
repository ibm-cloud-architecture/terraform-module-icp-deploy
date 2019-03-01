# Tests for the deploy module

Various unit and validation tests for the module.

Most tests run individual scripts in containers to validate expected behavior.
This allows the scripts to easily be validated in a number of linux distributions and versions.

There is a helper script `container-runtest.sh` which will run inside the test container.
The script will setup the directory structure, install pre-requisites and run validation tests.
`container-runtest.sh` will return the sum of tested script exit code + validation code exit code.

## Pre-requisits

To run the tests you'll need the following installed

- [BATS](https://github.com/bats-core/bats-core)
- [Terraform](https://www.terraform.io/)
- Docker (it must be running)

## Running tests

To run all existing tests
```
./run_bats.sh all
```

To run single test, for example load-image
```
./run_bats.sh load-image.bats
```


Most tests are run in docker containers, so you can monitor the tests by running
`docker logs -f <container_id>` on the active container
