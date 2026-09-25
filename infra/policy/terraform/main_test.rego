package main

import rego.v1

# Chay: `conftest verify --policy policy/terraform` tu thu muc infra/.

full_tags := {
	"project": "insighthub",
	"environment": "dev",
	"owner": "lamduy2002",
	"cost_center": "DO2603",
	"managed_by": "terraform",
	"ExpiresAt": "2026-09-24T23:59:00+07:00",
}

mk(addr, type, after) := {
	"address": addr,
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

valid_rds_after := {
	"tags_all": full_tags,
	"storage_encrypted": true,
	"publicly_accessible": false,
	"instance_class": "db.t3.micro",
	"engine_version": "16.15",
	"multi_az": false,
	"parameter_group_name": "insighthub-postgres16",
}

valid_pg_after := {
	"tags_all": full_tags,
	"name": "insighthub-postgres16",
	"family": "postgres16",
	"parameter": [{"name": "rds.force_ssl", "value": "1", "apply_method": "immediate"}],
}

pg_rc := mk("module.data.aws_db_parameter_group.postgres", "aws_db_parameter_group", valid_pg_after)

valid_redis_after := {
	"tags_all": full_tags,
	"at_rest_encryption_enabled": "true",
	"transit_encryption_enabled": true,
	"node_type": "cache.t3.micro",
	"engine_version": "7.1",
}

valid_ecr_after := {
	"tags_all": full_tags,
	"encryption_configuration": [{"encryption_type": "KMS"}],
}

valid_eks_cluster_after := {
	"tags_all": full_tags,
	"vpc_config": [{"public_access_cidrs": ["203.0.113.10/32"]}],
}

valid_eks_node_after := {
	"tags_all": full_tags,
	"instance_types": ["t3.medium"],
}

valid_sg_after := {
	"tags_all": full_tags,
	"ingress": [
		{"from_port": 5432, "to_port": 5432, "cidr_blocks": [], "ipv6_cidr_blocks": []},
		{"from_port": 6379, "to_port": 6379, "cidr_blocks": [], "ipv6_cidr_blocks": []},
	],
}

valid_iam_attach_after := {"policy_arn": "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"}

valid_vpc_after := {"tags_all": full_tags}

valid_input := {"resource_changes": [
	mk("aws_vpc.lab", "aws_vpc", valid_vpc_after),
	mk("aws_db_instance.postgres", "aws_db_instance", valid_rds_after),
	pg_rc,
	mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", valid_redis_after),
	mk("aws_ecr_repository.app[\"api\"]", "aws_ecr_repository", valid_ecr_after),
	mk("aws_eks_cluster.lab", "aws_eks_cluster", valid_eks_cluster_after),
	mk("aws_eks_node_group.lab", "aws_eks_node_group", valid_eks_node_after),
	mk("aws_security_group.data", "aws_security_group", valid_sg_after),
	mk("aws_iam_role_policy_attachment.eks_cluster_policy", "aws_iam_role_policy_attachment", valid_iam_attach_after),
]}

# ---- 1 test allow tren input hop le day du ----
test_allow_full_valid_input if {
	count(deny) == 0 with input as valid_input
}

# ---- Tags ----
test_deny_tags_missing_owner if {
	bad_tags := {
		"project": "insighthub", "environment": "dev",
		"cost_center": "DO2603", "managed_by": "terraform",
		"ExpiresAt": "2026-09-24T23:59:00+07:00",
	}
	some msg in deny with input as {"resource_changes": [mk("aws_vpc.lab", "aws_vpc", {"tags_all": bad_tags})]}
	contains(msg, "owner")
}

# ---- storage_encrypted ----
test_deny_rds_not_encrypted if {
	after := object.union(valid_rds_after, {"storage_encrypted": false})
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", after)]}
	contains(msg, "storage_encrypted")
}

# ---- at_rest_encryption_enabled: ca 2 dang true/"true" deu allow; false/"false"/thieu deu deny ----
test_allow_at_rest_bool_true if {
	after := object.union(valid_redis_after, {"at_rest_encryption_enabled": true})
	msgs := {msg | some msg in deny; contains(msg, "at_rest_encryption_enabled")} with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	count(msgs) == 0
}

test_allow_at_rest_string_true if {
	after := object.union(valid_redis_after, {"at_rest_encryption_enabled": "true"})
	msgs := {msg | some msg in deny; contains(msg, "at_rest_encryption_enabled")} with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	count(msgs) == 0
}

test_deny_at_rest_bool_false if {
	after := object.union(valid_redis_after, {"at_rest_encryption_enabled": false})
	some msg in deny with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	contains(msg, "at_rest_encryption_enabled")
}

test_deny_at_rest_string_false if {
	after := object.union(valid_redis_after, {"at_rest_encryption_enabled": "false"})
	some msg in deny with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	contains(msg, "at_rest_encryption_enabled")
}

test_deny_at_rest_missing if {
	after := {k: v |
		some k, v in valid_redis_after
		k != "at_rest_encryption_enabled"
	}
	some msg in deny with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	contains(msg, "at_rest_encryption_enabled")
}

# ---- transit_encryption_enabled ----
test_deny_redis_not_transit_encrypted if {
	after := object.union(valid_redis_after, {"transit_encryption_enabled": false})
	some msg in deny with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	contains(msg, "transit_encryption_enabled")
}

# ---- ECR encryption ----
test_deny_ecr_missing_encryption_configuration if {
	after := {"tags_all": full_tags, "encryption_configuration": []}
	some msg in deny with input as {"resource_changes": [mk("aws_ecr_repository.app[\"api\"]", "aws_ecr_repository", after)]}
	contains(msg, "encryption_configuration")
}

test_deny_ecr_wrong_encryption_type if {
	after := object.union(valid_ecr_after, {"encryption_configuration": [{"encryption_type": "AES256"}]})
	some msg in deny with input as {"resource_changes": [mk("aws_ecr_repository.app[\"api\"]", "aws_ecr_repository", after)]}
	contains(msg, "encryption_type")
}

# ---- Engine version pin ----
test_deny_rds_wrong_engine_version if {
	after := object.union(valid_rds_after, {"engine_version": "15.4"})
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", after)]}
	contains(msg, "engine_version")
}

test_deny_redis_wrong_engine_version if {
	after := object.union(valid_redis_after, {"engine_version": "6.2"})
	some msg in deny with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	contains(msg, "engine_version")
}

# ---- Not public ----
test_deny_rds_publicly_accessible if {
	after := object.union(valid_rds_after, {"publicly_accessible": true})
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", after)]}
	contains(msg, "publicly_accessible")
}

test_deny_sg_open_ipv4_5432 if {
	after := {"tags_all": full_tags, "ingress": [{"from_port": 5432, "to_port": 5432, "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": []}]}
	some msg in deny with input as {"resource_changes": [mk("aws_security_group.data", "aws_security_group", after)]}
	contains(msg, "0.0.0.0/0")
}

test_deny_sg_open_ipv6_6379 if {
	after := {"tags_all": full_tags, "ingress": [{"from_port": 6379, "to_port": 6379, "cidr_blocks": [], "ipv6_cidr_blocks": ["::/0"]}]}
	some msg in deny with input as {"resource_changes": [mk("aws_security_group.data", "aws_security_group", after)]}
	contains(msg, "::/0")
}

test_deny_eks_public_access_cidrs_open if {
	after := object.union(valid_eks_cluster_after, {"vpc_config": [{"public_access_cidrs": ["0.0.0.0/0"]}]})
	some msg in deny with input as {"resource_changes": [mk("aws_eks_cluster.lab", "aws_eks_cluster", after)]}
	contains(msg, "public_access_cidrs")
}

# ---- rds.force_ssl ----
test_allow_rds_with_force_ssl_parameter_group if {
	count(deny) == 0 with input as {"resource_changes": [
		mk("aws_db_instance.postgres", "aws_db_instance", valid_rds_after),
		pg_rc,
	]}
}

test_deny_rds_without_parameter_group if {
	after := object.remove(valid_rds_after, ["parameter_group_name"])
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", after), pg_rc]}
	contains(msg, "rds.force_ssl")
}

test_deny_rds_parameter_group_not_in_plan if {
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", valid_rds_after)]}
	contains(msg, "rds.force_ssl")
}

test_deny_rds_force_ssl_zero if {
	pg_after := object.union(valid_pg_after, {"parameter": [{"name": "rds.force_ssl", "value": "0", "apply_method": "immediate"}]})
	some msg in deny with input as {"resource_changes": [
		mk("aws_db_instance.postgres", "aws_db_instance", valid_rds_after),
		mk("module.data.aws_db_parameter_group.postgres", "aws_db_parameter_group", pg_after),
	]}
	contains(msg, "rds.force_ssl")
}

# ---- Cost guardrail ----
test_deny_eks_node_type_outside_allowlist if {
	after := object.union(valid_eks_node_after, {"instance_types": ["m5.large"]})
	some msg in deny with input as {"resource_changes": [mk("aws_eks_node_group.lab", "aws_eks_node_group", after)]}
	contains(msg, "instance_types")
}

test_deny_rds_instance_class_outside_allowlist if {
	after := object.union(valid_rds_after, {"instance_class": "db.m5.large"})
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", after)]}
	contains(msg, "instance_class")
}

test_deny_redis_node_type_outside_allowlist if {
	after := object.union(valid_redis_after, {"node_type": "cache.m5.large"})
	some msg in deny with input as {"resource_changes": [mk("aws_elasticache_replication_group.redis", "aws_elasticache_replication_group", after)]}
	contains(msg, "node_type")
}

test_deny_nat_gateway_forbidden if {
	after := {"tags_all": full_tags}
	some msg in deny with input as {"resource_changes": [mk("aws_nat_gateway.x", "aws_nat_gateway", after)]}
	contains(msg, "aws_nat_gateway")
}

test_deny_rds_multi_az_true if {
	after := object.union(valid_rds_after, {"multi_az": true})
	some msg in deny with input as {"resource_changes": [mk("aws_db_instance.postgres", "aws_db_instance", after)]}
	contains(msg, "multi_az")
}

test_deny_admin_access_attachment if {
	after := {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"}
	some msg in deny with input as {"resource_changes": [mk("aws_iam_role_policy_attachment.bad", "aws_iam_role_policy_attachment", after)]}
	contains(msg, "AdministratorAccess")
}
