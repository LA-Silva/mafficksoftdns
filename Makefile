
SRCS := $(shell find . -name "*.go" -not -path "./vendor/*")

# this is the main binary
# set MAFSDEVOPS to 1 if you want also version control and testing.
bin/mfsdns: $(SRCS)
	@echo "Changes detected. Building..."
	go build -ldflags="-s -w" -o bin/mfsdns main.go
	@if [ "$$MAFSDEVOPS" = "1" ]; then \
		echo "MAFSDEVOPS - Staging files " && \
		git add . && \
		echo "MAFSDEVOPS - Test scripts" && \
		bash scripts/test.sh && \
		echo "MAFSDEVOPS - Tests ok - commiting work " && \
		git commit . && \
		git push && \
		echo "MAFSDEVOPS -DONE-" ; \
	else \
		echo "MAFSDEVOPS is not set to 1. Skipping git add."; \
	fi


clean :
	rm bin/mfsdns
