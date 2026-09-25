package main

import rego.v1

# Conftest 0.70.1 / OPA 1.20.2 pin — cu phap Rego v1 (deny contains msg if {...}),
# khong dung deny[msg] { } kieu cu. Chay: `conftest test --policy policy/terraform
# tfplan.json` tu thu muc infra/ (SPEC.md Muc 11).

required_tags := {"project", "environment", "owner", "cost_center", "managed_by", "ExpiresAt"}
allowed_eks_node_types := {"t3.medium"}
allowed_rds_instance_classes := {"db.t3.micro"}
allowed_redis_node_types := {"cache.t3.micro"}
sensitive_ports := {5432, 6379}

# hashicorp/aws ~> 5.70 (pin 5.100.0 tai thoi diem viet) serialize
# aws_elasticache_replication_group.at_rest_encryption_enabled dang STRING
# "true"/"false" trong resource_changes[].change.after (schema TypeString
# cho field nay vi ly do lich su cua provider), trong khi
# transit_encryption_enabled/storage_encrypted/publicly_accessible/multi_az
# la boolean binh thuong. is_true() chap nhan ca 2 dang de rule khong
# false-positive tren plan that (xem SPEC.md Muc 11).
is_true(v) if v == true

is_true(v) if v == "true"

# Bo qua resource dang bi xoa (khong con "after" de kiem tra trang thai dich).
is_active(rc) if {
	rc.change.after != null
	rc.change.actions != ["delete"]
}

# ============================================================
# Tags — moi resource ho tro tag (co tags_all, tu default_tags) phai du
# project/environment/owner/cost_center/managed_by/ExpiresAt, khong rong.
# ============================================================
deny contains msg if {
	some rc in input.resource_changes
	rc.mode == "managed"
	is_active(rc)
	tags_all := object.get(rc.change.after, "tags_all", null)
	tags_all != null
	some tag in required_tags
	val := object.get(tags_all, tag, "")
	val == ""
	msg := sprintf("%s: tag bat buoc '%s' thieu hoac rong", [rc.address, tag])
}

# ============================================================
# Encryption — phai bat (is_true), thieu field cung bi tinh la vi pham.
# ============================================================
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	is_active(rc)
	v := object.get(rc.change.after, "storage_encrypted", null)
	not is_true(v)
	msg := sprintf("%s: storage_encrypted phai la true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_elasticache_replication_group"
	is_active(rc)
	v := object.get(rc.change.after, "at_rest_encryption_enabled", null)
	not is_true(v)
	msg := sprintf("%s: at_rest_encryption_enabled phai la true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_elasticache_replication_group"
	is_active(rc)
	v := object.get(rc.change.after, "transit_encryption_enabled", null)
	not is_true(v)
	msg := sprintf("%s: transit_encryption_enabled phai la true", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	is_active(rc)
	enc := object.get(rc.change.after, "encryption_configuration", [])
	count(enc) == 0
	msg := sprintf("%s: thieu encryption_configuration (can KMS)", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	is_active(rc)
	enc := object.get(rc.change.after, "encryption_configuration", [])
	count(enc) > 0
	enc[0].encryption_type != "KMS"
	msg := sprintf("%s: encryption_type phai la KMS", [rc.address])
}

# TLS bắt buộc phía server: mỗi aws_db_instance phải gắn parameter group
# (có trong plan) đặt rds.force_ssl = "1". Kiểm được qua plan vì
# parameter_group_name và name của aws_db_parameter_group đều cố định
# (không name_prefix) nên đã biết lúc plan. Thiếu parameter group, tên
# không khớp, hoặc giá trị khác "1" → deny (fail-closed). SPEC.md Mục 11.
force_ssl_parameter_group(name) if {
	some pg in input.resource_changes
	pg.type == "aws_db_parameter_group"
	is_active(pg)
	pg.change.after.name == name
	some p in object.get(pg.change.after, "parameter", [])
	p.name == "rds.force_ssl"
	p.value == "1"
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	is_active(rc)
	pg_name := object.get(rc.change.after, "parameter_group_name", "")
	not force_ssl_parameter_group(pg_name)
	msg := sprintf("%s: parameter_group_name '%s' phai tro toi aws_db_parameter_group co rds.force_ssl = 1 (bat buoc TLS)", [rc.address, pg_name])
}

# ============================================================
# Engine version pin
# ============================================================
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	is_active(rc)
	ev := object.get(rc.change.after, "engine_version", "")
	not startswith(ev, "16")
	msg := sprintf("%s: engine_version '%s' phai bat dau bang 16", [rc.address, ev])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_elasticache_replication_group"
	is_active(rc)
	ev := object.get(rc.change.after, "engine_version", "")
	not startswith(ev, "7")
	msg := sprintf("%s: engine_version '%s' phai bat dau bang 7", [rc.address, ev])
}

# ============================================================
# Not public — phai tat (is_true => deny)
# ============================================================
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	is_active(rc)
	v := object.get(rc.change.after, "publicly_accessible", false)
	is_true(v)
	msg := sprintf("%s: publicly_accessible phai la false", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group"
	is_active(rc)
	some ing in object.get(rc.change.after, "ingress", [])
	some cidr in object.get(ing, "cidr_blocks", [])
	cidr == "0.0.0.0/0"
	some port in sensitive_ports
	ing.from_port <= port
	port <= ing.to_port
	msg := sprintf("%s: ingress cho phep 0.0.0.0/0 toi port %d", [rc.address, port])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group"
	is_active(rc)
	some ing in object.get(rc.change.after, "ingress", [])
	some cidr in object.get(ing, "ipv6_cidr_blocks", [])
	cidr == "::/0"
	some port in sensitive_ports
	ing.from_port <= port
	port <= ing.to_port
	msg := sprintf("%s: ingress cho phep ::/0 toi port %d", [rc.address, port])
}

# Bu cho CKV_AWS_38 (checkov phai #checkov:skip vi khong resolve tinh duoc
# var.admin_cidrs) — Conftest doc gia tri THAT trong plan JSON nen bat duoc
# neu admin_cidrs vo tinh chua 0.0.0.0/0 (vd validation bi sua/bo).
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_eks_cluster"
	is_active(rc)
	vpc_cfg := rc.change.after.vpc_config[0]
	some cidr in object.get(vpc_cfg, "public_access_cidrs", [])
	cidr == "0.0.0.0/0"
	msg := sprintf("%s: public_access_cidrs khong duoc chua 0.0.0.0/0", [rc.address])
}

# ============================================================
# Cost guardrail
# ============================================================
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_eks_node_group"
	is_active(rc)
	some itype in rc.change.after.instance_types
	not allowed_eks_node_types[itype]
	msg := sprintf("%s: instance_types '%s' khong nam trong allowlist %v", [rc.address, itype, allowed_eks_node_types])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	is_active(rc)
	ic := object.get(rc.change.after, "instance_class", "")
	not allowed_rds_instance_classes[ic]
	msg := sprintf("%s: instance_class '%s' khong nam trong allowlist %v", [rc.address, ic, allowed_rds_instance_classes])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_elasticache_replication_group"
	is_active(rc)
	nt := object.get(rc.change.after, "node_type", "")
	not allowed_redis_node_types[nt]
	msg := sprintf("%s: node_type '%s' khong nam trong allowlist %v", [rc.address, nt, allowed_redis_node_types])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_nat_gateway"
	some a in rc.change.actions
	a == "create"
	msg := sprintf("%s: cam tao aws_nat_gateway (cost guardrail)", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_db_instance"
	is_active(rc)
	v := object.get(rc.change.after, "multi_az", false)
	is_true(v)
	msg := sprintf("%s: multi_az phai la false (cost guardrail)", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_iam_role_policy_attachment"
	is_active(rc)
	arn := object.get(rc.change.after, "policy_arn", "")
	endswith(arn, "/AdministratorAccess")
	msg := sprintf("%s: cam gan policy_arn ket thuc bang /AdministratorAccess", [rc.address])
}
