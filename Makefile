.PHONY: bootstrap lint test validate security

bootstrap:
	bash scripts/bootstrap.sh

lint:
	bash scripts/lint.sh

test:
	bash scripts/test-fixtures.sh

validate:
	bash scripts/validate-workflows.sh .

security:
	bash scripts/security.sh
