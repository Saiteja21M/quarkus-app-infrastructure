terraform-plan: $(call TERRAFORM_PLAN)

define TERRAFORM_APPLY
	$(MAKE) fmt
	cd $(MAIN_DIR)/cluster/$(1) && \
	terraform apply
endef

define TERRAFORM_PLAN
	cd C:\projects\Work\EC2-Demo\terraform\ && \
	terraform init && \
	terraform apply
endef