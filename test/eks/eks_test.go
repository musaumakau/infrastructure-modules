// Package eks_test contains production-grade Terratest integration tests for the EKS module.
//
// Estimated runtime : 35–50 min per full lifecycle test
// Estimated cost    : ~$0.30–0.50 per full run (EKS + NAT gateway + EC2 nodes)
// Run with          : go test -v -timeout 90m -run TestEKSLifecycle ./...
//
// Environment variables:
//
//	TEST_AWS_REGION   — AWS region to deploy into (default: eu-west-1)
//
// Parallelism note  : Full lifecycle tests are intentionally sequential — they each
//
//	provision a VPC + EKS cluster and run for 35+ minutes. Running
//	them in parallel in the same AWS account risks hitting service
//	quotas (EKS clusters, NAT gateways, EIPs). Use parallel only for
//	lightweight, isolated unit-style checks.
package eks_test

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/kms"
	awsTerratest "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// ---------------------------------------------------------------------------
// Config — values mirror the live terragrunt deployment exactly.
// Region is read from TEST_AWS_REGION; all other values match inputs in
// the terragrunt stack (eks_name, ami_type, instance_types, tags, etc.)
// ---------------------------------------------------------------------------

const (
	// eksName mirrors `eks_name = "demo"` in the terragrunt inputs.
	eksName = "demo"
	// eksVersion mirrors `eks_version = "1.33"`.
	eksVersion = "1.33"
	// testEnv is the env prefix used for test-only resources; it is NOT the
	// live env value (which comes from env.hcl in the real stack).
	testEnv = "terratest"

	// nodeGroupName mirrors the key in the node_groups map.
	nodeGroupName = "general"
	// nodeAMIType mirrors `ami_type = "AL2023_ARM_64_STANDARD"`.
	nodeAMIType = "AL2023_ARM_64_STANDARD"
	// nodeInstanceType mirrors `instance_types = ["t4g.xlarge"]`.
	nodeInstanceType = "t4g.xlarge"
	// nodeMinSize / nodeMaxSize mirror the scaling_config in the terragrunt inputs.
	nodeMinSize = int64(0)
	nodeMaxSize = int64(2)

	// githubActionsRoleARN mirrors `github_actions_role_arn` in the terragrunt inputs.
	// Account ID 649203810550 is the real deployment account.
	githubActionsRoleARN = "arn:aws:iam::649203810550:role/EksOIDCRole"

	// Retry knobs
	retryMaxRetries   = 40
	retrySleepBetween = 15 * time.Second
)

// awsRegion returns the region to use, preferring the TEST_AWS_REGION env var
// and falling back to eu-west-1 (the live deployment region).
func awsRegion() string {
	if r := os.Getenv("TEST_AWS_REGION"); r != "" {
		return r
	}
	return "eu-west-1"
}

// ---------------------------------------------------------------------------
// AWS client bundle — initialised once per test, passed around as a value
// ---------------------------------------------------------------------------

type awsClients struct {
	eks *eks.EKS
	kms *kms.KMS
	iam *iam.IAM
	ec2 *ec2.EC2
}

func newAWSClients(t *testing.T) awsClients {
	t.Helper()
	sess, err := session.NewSession(&aws.Config{Region: aws.String(awsRegion())})
	require.NoError(t, err, "failed to create AWS session")
	return awsClients{
		eks: eks.New(sess),
		kms: kms.New(sess),
		iam: iam.New(sess),
		ec2: ec2.New(sess),
	}
}

// ---------------------------------------------------------------------------
// Cached AWS resource fetchers — call once, reuse across sub-tests
// ---------------------------------------------------------------------------

// getCluster fetches and returns the EKS cluster description, failing the test on error.
func getCluster(t *testing.T, client *eks.EKS, clusterName string) *eks.Cluster {
	t.Helper()
	out, err := client.DescribeCluster(&eks.DescribeClusterInput{
		Name: aws.String(clusterName),
	})
	require.NoError(t, err, "DescribeCluster failed for %s", clusterName)
	return out.Cluster
}

// getNodeGroup fetches and returns a named node group, failing the test on error.
func getNodeGroup(t *testing.T, client *eks.EKS, clusterName, nodeGroupName string) *eks.Nodegroup {
	t.Helper()
	out, err := client.DescribeNodegroup(&eks.DescribeNodegroupInput{
		ClusterName:   aws.String(clusterName),
		NodegroupName: aws.String(nodeGroupName),
	})
	require.NoError(t, err, "DescribeNodegroup failed for %s/%s", clusterName, nodeGroupName)
	return out.Nodegroup
}

// listNodeGroupNames returns all node group names for a cluster.
func listNodeGroupNames(t *testing.T, client *eks.EKS, clusterName string) []string {
	t.Helper()
	out, err := client.ListNodegroups(&eks.ListNodegroupsInput{
		ClusterName: aws.String(clusterName),
	})
	require.NoError(t, err, "ListNodegroups failed for %s", clusterName)
	names := make([]string, 0, len(out.Nodegroups))
	for _, n := range out.Nodegroups {
		names = append(names, aws.StringValue(n))
	}
	return names
}

// ---------------------------------------------------------------------------
// Retry-based readiness helpers
// ---------------------------------------------------------------------------

// waitForClusterActive polls until the cluster reaches ACTIVE state or the
// retry budget is exhausted.
func waitForClusterActive(t *testing.T, client *eks.EKS, clusterName string) {
	t.Helper()
	description := fmt.Sprintf("waiting for EKS cluster %s to become ACTIVE", clusterName)
	_, err := retry.DoWithRetryE(t, description, retryMaxRetries, retrySleepBetween, func() (string, error) {
		cluster := getCluster(t, client, clusterName)
		status := aws.StringValue(cluster.Status)
		if status != "ACTIVE" {
			return "", fmt.Errorf("cluster status is %s, want ACTIVE", status)
		}
		return status, nil
	})
	require.NoError(t, err, "EKS cluster never reached ACTIVE state")
}

// waitForNodeGroupActive polls until the named node group reaches ACTIVE state.
func waitForNodeGroupActive(t *testing.T, client *eks.EKS, clusterName, nodeGroupName string) {
	t.Helper()
	description := fmt.Sprintf("waiting for node group %s to become ACTIVE", nodeGroupName)
	_, err := retry.DoWithRetryE(t, description, retryMaxRetries, retrySleepBetween, func() (string, error) {
		ng := getNodeGroup(t, client, clusterName, nodeGroupName)
		status := aws.StringValue(ng.Status)
		if status != "ACTIVE" {
			return "", fmt.Errorf("node group status is %s, want ACTIVE", status)
		}
		return status, nil
	})
	require.NoError(t, err, "Node group never reached ACTIVE state")
}

// ---------------------------------------------------------------------------
// Terraform options builders
// ---------------------------------------------------------------------------

func vpcTerraformOptions(t *testing.T, env, cidrBlock string, azs, privateCIDRs, publicCIDRs []string) *terraform.Options {
	t.Helper()
	region := awsRegion()
	return terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../vpc",
		Vars: map[string]interface{}{
			"env":    env,
			"region": region,

			"vpc_cidr_block":       cidrBlock,
			"azs":                  azs,
			"private_subnet_cidrs": privateCIDRs,
			"public_subnet_cidrs":  publicCIDRs,

			"private_subnet_tags": map[string]string{
				"kubernetes.io/role/internal-elb": "1",
			},
			"public_subnet_tags": map[string]string{
				"kubernetes.io/role/elb": "1",
			},

			// Tags match the live terragrunt stack exactly
			"project":     "infrastructure-modules",
			"environment": "test",
			"owner":       "engineering",
			"cost_center": "CC-0001",
		},
		NoColor: true,
	})
}

func eksTerraformOptions(t *testing.T, env, vpcID string, subnetIDs []string) *terraform.Options {
	t.Helper()
	region := awsRegion()
	return terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../eks",
		Vars: map[string]interface{}{
			"env":         env,
			"region":      region,
			"eks_name":    eksName,
			"eks_version": eksVersion,

			"vpc_id":     vpcID,
			"subnet_ids": subnetIDs,

			// Matches `github_actions_role_arn` in the live terragrunt inputs.
			"github_actions_role_arn": githubActionsRoleARN,

			"enable_irsa": true,
			// Matches `admin_principal_arns` in the live terragrunt inputs.
			"admin_principal_arns": []string{"arn:aws:iam::649203810550:user/Kay"},

			// node_groups key and all nested values match the live "general" group exactly.
			"node_groups": map[string]interface{}{
				nodeGroupName: map[string]interface{}{
					"capacity_type":  "ON_DEMAND",
					"instance_types": []string{nodeInstanceType}, // t4g.xlarge
					"disk_size":      20,
					"ami_type":       nodeAMIType, // AL2023_ARM_64_STANDARD
					"labels":         map[string]string{},
					"taints":         []interface{}{},
					"scaling_config": map[string]interface{}{
						"desired_size": 1,
						"max_size":     nodeMaxSize, // 2
						"min_size":     nodeMinSize, // 0
					},
				},
			},

			// Tags match the live terragrunt stack exactly.
			"project":     "infrastructure-modules",
			"environment": "ci-mock",
			"owner":       "engineering",
			"cost_center": "CC-0001",
		},
		NoColor: true,
	})
}

// ---------------------------------------------------------------------------
// Governance tag assertion helper
// ---------------------------------------------------------------------------

// requiredTags defines the tag keys and values every resource must carry.
// Values mirror the live terragrunt inputs exactly.
var requiredTags = map[string]string{
	"Project":     "infrastructure-modules",
	"Environment": "test",
	"Owner":       "engineering", // matches `owner = "engineering"` in terragrunt inputs
	"CostCenter":  "CC-0001",
}

func assertTags(t *testing.T, resource string, actual map[string]*string) {
	t.Helper()
	for k, want := range requiredTags {
		v, ok := actual[k]
		assert.True(t, ok, "%s: missing required tag %q", resource, k)
		if ok {
			assert.Equal(t, want, aws.StringValue(v), "%s: tag %q = %q, want %q", resource, k, aws.StringValue(v), want)
		}
	}
}

// ---------------------------------------------------------------------------
// Kubernetes client builder
// ---------------------------------------------------------------------------

// newK8sClientset builds a Kubernetes clientset from a kubeconfig file path.
func newK8sClientset(t *testing.T, kubeconfigPath string) *kubernetes.Clientset {
	t.Helper()
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfigPath)
	require.NoError(t, err, "failed to build kubeconfig")
	clientset, err := kubernetes.NewForConfig(config)
	require.NoError(t, err, "failed to create Kubernetes clientset")
	return clientset
}

// ---------------------------------------------------------------------------
// Test 1 — Full EKS lifecycle (sequential, covers all assertion groups)
// ---------------------------------------------------------------------------

func TestEKSLifecycle(t *testing.T) {
	// NOT parallel — provisions VPC + EKS; runs 35–50 min; risks quota exhaustion
	// if stacked with other full-lifecycle tests.

	// ── Step 1: VPC ─────────────────────────────────────────────────────────
	vpcOpts := vpcTerraformOptions(t,
		fmt.Sprintf("%s-eks-prereq", testEnv),
		"10.97.0.0/16",
		[]string{awsRegion() + "a", awsRegion() + "b"},
		[]string{"10.97.1.0/24", "10.97.2.0/24"},
		[]string{"10.97.101.0/24", "10.97.102.0/24"},
	)
	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	privateIDs := terraform.OutputList(t, vpcOpts, "private_subnet_ids")

	// ── Step 2: EKS ─────────────────────────────────────────────────────────
	eksOpts := eksTerraformOptions(t, testEnv, vpcID, privateIDs)
	defer terraform.Destroy(t, eksOpts)
	terraform.InitAndApply(t, eksOpts)

	clusterName := terraform.Output(t, eksOpts, "eks_name")
	oidcIssuerURL := terraform.Output(t, eksOpts, "cluster_oidc_issuer_url")
	oidcProviderARN := terraform.Output(t, eksOpts, "openid_provider_arn")
	kubeconfigPath := terraform.Output(t, eksOpts, "kubeconfig_path")

	// ── Initialise clients ──────────────────────────────────────────────────
	clients := newAWSClients(t)

	// ── Wait for resources to be truly ready ───────────────────────────────
	waitForClusterActive(t, clients.eks, clusterName)
	waitForNodeGroupActive(t, clients.eks, clusterName, nodeGroupName)

	// ── Fetch resources ONCE; reuse across all sub-tests ───────────────────
	cluster := getCluster(t, clients.eks, clusterName)
	nodeGroup := getNodeGroup(t, clients.eks, clusterName, nodeGroupName)

	// ════════════════════════════════════════════════════════════════════════
	// Group A — Cluster health
	// ════════════════════════════════════════════════════════════════════════

	t.Run("cluster_name_follows_convention", func(t *testing.T) {
		expected := fmt.Sprintf("%s-%s", testEnv, eksName)
		assert.Equal(t, expected, clusterName,
			"cluster name must follow <env>-<eks_name> convention")
	})

	t.Run("cluster_is_active", func(t *testing.T) {
		assert.Equal(t, "ACTIVE", aws.StringValue(cluster.Status))
	})

	t.Run("cluster_version_matches", func(t *testing.T) {
		assert.Equal(t, eksVersion, aws.StringValue(cluster.Version))
	})

	// ════════════════════════════════════════════════════════════════════════
	// Group B — Security (encryption, KMS, logging, endpoints)
	// ════════════════════════════════════════════════════════════════════════

	t.Run("secrets_encryption_enabled", func(t *testing.T) {
		require.NotEmpty(t, cluster.EncryptionConfig, "cluster must have encryption config")
		cfg := cluster.EncryptionConfig[0]
		assert.Contains(t, cfg.Resources, aws.String("secrets"))
		assert.NotEmpty(t, aws.StringValue(cfg.Provider.KeyArn), "encryption must reference a KMS key ARN")
	})

	t.Run("kms_key_rotation_enabled", func(t *testing.T) {
		require.NotEmpty(t, cluster.EncryptionConfig)
		keyARN := aws.StringValue(cluster.EncryptionConfig[0].Provider.KeyArn)

		rotOut, err := clients.kms.GetKeyRotationStatus(&kms.GetKeyRotationStatusInput{
			KeyId: aws.String(keyARN),
		})
		require.NoError(t, err)
		assert.True(t, aws.BoolValue(rotOut.KeyRotationEnabled), "KMS key must have automatic rotation enabled")
	})

	t.Run("kms_key_governance_tags", func(t *testing.T) {
		require.NotEmpty(t, cluster.EncryptionConfig)
		keyARN := aws.StringValue(cluster.EncryptionConfig[0].Provider.KeyArn)

		tagsOut, err := clients.kms.ListResourceTags(&kms.ListResourceTagsInput{
			KeyId: aws.String(keyARN),
		})
		require.NoError(t, err)

		tagMap := make(map[string]*string, len(tagsOut.Tags))
		for _, tag := range tagsOut.Tags {
			tagMap[aws.StringValue(tag.TagKey)] = tag.TagValue
		}
		assertTags(t, "KMS key", tagMap)
	})

	t.Run("control_plane_logging_fully_enabled", func(t *testing.T) {
		var enabled []string
		for _, cfg := range cluster.Logging.ClusterLogging {
			if aws.BoolValue(cfg.Enabled) {
				for _, lt := range cfg.Types {
					enabled = append(enabled, aws.StringValue(lt))
				}
			}
		}
		required := []string{"api", "audit", "authenticator", "controllerManager", "scheduler"}
		for _, r := range required {
			assert.Contains(t, enabled, r, "log type %q must be enabled", r)
		}
	})

	t.Run("private_endpoint_enabled", func(t *testing.T) {
		assert.True(t, aws.BoolValue(cluster.ResourcesVpcConfig.EndpointPrivateAccess),
			"private endpoint access must be enabled")
	})

	t.Run("public_endpoint_disabled_or_restricted", func(t *testing.T) {
		vpc := cluster.ResourcesVpcConfig
		if aws.BoolValue(vpc.EndpointPublicAccess) {
			// Public access is on — it must be restricted to known CIDRs (not 0.0.0.0/0)
			for _, cidr := range vpc.PublicAccessCidrs {
				assert.NotEqual(t, "0.0.0.0/0", aws.StringValue(cidr),
					"public endpoint must not be open to the world; restrict to known CIDRs")
			}
		}
	})

	// ════════════════════════════════════════════════════════════════════════
	// Group C — Networking
	// ════════════════════════════════════════════════════════════════════════

	t.Run("cluster_in_correct_vpc", func(t *testing.T) {
		assert.Equal(t, vpcID, aws.StringValue(cluster.ResourcesVpcConfig.VpcId))
	})

	t.Run("cluster_security_group_has_governance_tags", func(t *testing.T) {
		sgID := aws.StringValue(cluster.ResourcesVpcConfig.ClusterSecurityGroupId)
		require.NotEmpty(t, sgID)

		out, err := clients.ec2.DescribeSecurityGroups(&ec2.DescribeSecurityGroupsInput{
			GroupIds: []*string{aws.String(sgID)},
		})
		require.NoError(t, err)
		require.Len(t, out.SecurityGroups, 1)

		tagMap := make(map[string]*string)
		for _, tag := range out.SecurityGroups[0].Tags {
			tagMap[aws.StringValue(tag.Key)] = tag.Value
		}
		assertTags(t, fmt.Sprintf("security group %s", sgID), tagMap)
	})

	// ════════════════════════════════════════════════════════════════════════
	// Group D — Node groups
	// ════════════════════════════════════════════════════════════════════════

	t.Run("node_group_exists_via_list", func(t *testing.T) {
		names := listNodeGroupNames(t, clients.eks, clusterName)
		assert.Contains(t, names, nodeGroupName, "node group %q must exist", nodeGroupName)
	})

	t.Run("node_group_is_active", func(t *testing.T) {
		assert.Equal(t, "ACTIVE", aws.StringValue(nodeGroup.Status))
	})

	t.Run("node_group_scaling_config", func(t *testing.T) {
		sc := nodeGroup.ScalingConfig
		assert.Equal(t, nodeMinSize, aws.Int64Value(sc.MinSize), "min_size must be %d", nodeMinSize)
		assert.Equal(t, nodeMaxSize, aws.Int64Value(sc.MaxSize), "max_size must be %d", nodeMaxSize)
	})

	t.Run("node_group_ami_type", func(t *testing.T) {
		// AL2023_ARM_64_STANDARD matches the t4g.xlarge (Graviton) instance type
		assert.Equal(t, nodeAMIType, aws.StringValue(nodeGroup.AmiType),
			"node group AMI type must match terragrunt inputs")
	})

	t.Run("node_group_in_private_subnets", func(t *testing.T) {
		for _, subnetID := range nodeGroup.Subnets {
			assert.Contains(t, privateIDs, aws.StringValue(subnetID),
				"node group subnet must be a private subnet")
		}
	})

	t.Run("node_group_governance_tags", func(t *testing.T) {
		assertTags(t, "node group", nodeGroup.Tags)
	})

	// ════════════════════════════════════════════════════════════════════════
	// Group E — IRSA / OIDC
	// ════════════════════════════════════════════════════════════════════════

	t.Run("oidc_issuer_url_populated", func(t *testing.T) {
		assert.NotEmpty(t, oidcIssuerURL)
	})

	t.Run("oidc_provider_arn_populated", func(t *testing.T) {
		assert.NotEmpty(t, oidcProviderARN)
	})

	t.Run("oidc_provider_exists_in_iam", func(t *testing.T) {
		_, err := clients.iam.GetOpenIDConnectProvider(&iam.GetOpenIDConnectProviderInput{
			OpenIDConnectProviderArn: aws.String(oidcProviderARN),
		})
		assert.NoError(t, err, "OIDC provider must exist in IAM — not just as a non-empty ARN string")
	})

	t.Run("oidc_issuer_matches_cluster", func(t *testing.T) {
		clusterIssuer := aws.StringValue(cluster.Identity.Oidc.Issuer)
		assert.Equal(t, clusterIssuer, oidcIssuerURL,
			"Terraform output cluster_oidc_issuer_url must match the cluster's OIDC issuer")
	})

	// ════════════════════════════════════════════════════════════════════════
	// Group F — Governance tags (cluster)
	// ════════════════════════════════════════════════════════════════════════

	t.Run("cluster_governance_tags", func(t *testing.T) {
		assertTags(t, "EKS cluster", cluster.Tags)
	})

	// ════════════════════════════════════════════════════════════════════════
	// Group G — Kubernetes-level validation
	// ════════════════════════════════════════════════════════════════════════

	t.Run("kubernetes_nodes_ready", func(t *testing.T) {
		clientset := newK8sClientset(t, kubeconfigPath)
		ctx := context.Background()

		_, err := retry.DoWithRetryE(t, "waiting for Ready nodes", 20, 15*time.Second, func() (string, error) {
			nodes, err := clientset.CoreV1().Nodes().List(ctx, metav1.ListOptions{})
			if err != nil {
				return "", err
			}
			for _, node := range nodes.Items {
				for _, cond := range node.Status.Conditions {
					if cond.Type == corev1.NodeReady && cond.Status != corev1.ConditionTrue {
						return "", fmt.Errorf("node %s not Ready", node.Name)
					}
				}
			}
			if len(nodes.Items) == 0 {
				return "", fmt.Errorf("no nodes registered yet")
			}
			return "ready", nil
		})
		assert.NoError(t, err, "all nodes must reach Ready state")
	})

	t.Run("kube_system_pods_running", func(t *testing.T) {
		clientset := newK8sClientset(t, kubeconfigPath)
		ctx := context.Background()

		_, err := retry.DoWithRetryE(t, "waiting for kube-system pods", 20, 15*time.Second, func() (string, error) {
			pods, err := clientset.CoreV1().Pods("kube-system").List(ctx, metav1.ListOptions{})
			if err != nil {
				return "", err
			}
			for _, pod := range pods.Items {
				if pod.Status.Phase != corev1.PodRunning && pod.Status.Phase != corev1.PodSucceeded {
					return "", fmt.Errorf("pod %s is in phase %s", pod.Name, pod.Status.Phase)
				}
			}
			if len(pods.Items) == 0 {
				return "", fmt.Errorf("no pods in kube-system yet")
			}
			return "ok", nil
		})
		assert.NoError(t, err, "all kube-system pods must be running")
	})
}

// ---------------------------------------------------------------------------
// Test 2 — IRSA disabled: no OIDC provider created
// ---------------------------------------------------------------------------

func TestEKSIRSADisabled(t *testing.T) {
	// Sequential — full VPC + EKS lifecycle; see parallelism note at top.

	vpcOpts := vpcTerraformOptions(t,
		fmt.Sprintf("%s-irsa-prereq", testEnv),
		"10.96.0.0/16",
		[]string{awsRegion() + "a", awsRegion() + "b"},
		[]string{"10.96.1.0/24", "10.96.2.0/24"},
		[]string{"10.96.101.0/24", "10.96.102.0/24"},
	)
	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	privateIDs := terraform.OutputList(t, vpcOpts, "private_subnet_ids")

	eksOpts := eksTerraformOptions(t, fmt.Sprintf("%s-noirsa", testEnv), vpcID, privateIDs)
	eksOpts.Vars["enable_irsa"] = false

	defer terraform.Destroy(t, eksOpts)
	terraform.InitAndApply(t, eksOpts)

	clusterName := terraform.Output(t, eksOpts, "eks_name")
	oidcProviderARN := terraform.Output(t, eksOpts, "openid_provider_arn")

	clients := newAWSClients(t)
	waitForClusterActive(t, clients.eks, clusterName)

	cluster := getCluster(t, clients.eks, clusterName)

	t.Run("oidc_provider_arn_is_empty", func(t *testing.T) {
		assert.Empty(t, oidcProviderARN,
			"openid_provider_arn output must be empty when enable_irsa = false")
	})

	t.Run("oidc_provider_does_not_exist_in_iam", func(t *testing.T) {
		// Derive what the ARN *would* be and confirm it doesn't exist.
		issuer := aws.StringValue(cluster.Identity.Oidc.Issuer)
		issuer = strings.TrimPrefix(issuer, "https://")
		accountID := awsTerratest.GetAccountId(t)
		wouldBeARN := fmt.Sprintf("arn:aws:iam::%s:oidc-provider/%s", accountID, issuer)

		_, err := clients.iam.GetOpenIDConnectProvider(&iam.GetOpenIDConnectProviderInput{
			OpenIDConnectProviderArn: aws.String(wouldBeARN),
		})
		assert.Error(t, err, "OIDC provider must NOT exist in IAM when enable_irsa = false")
	})

	t.Run("cluster_is_still_active", func(t *testing.T) {
		assert.Equal(t, "ACTIVE", aws.StringValue(cluster.Status),
			"cluster must be functional even without IRSA")
	})
}

// ---------------------------------------------------------------------------
// Test 3 — End-to-end workload validation (optional; tag with -run TestEKSE2E)
// Deploys nginx, waits for pod readiness, exposes via NodePort, validates HTTP 200.
// ---------------------------------------------------------------------------

func TestEKSE2E(t *testing.T) {
	// Requires a running cluster. In CI, chain after TestEKSLifecycle or provide
	// KUBECONFIG and CLUSTER_NAME env vars pointing to a pre-existing cluster.

	kubeconfigPath := terraform.Output(t, &terraform.Options{TerraformDir: "../../eks"}, "kubeconfig_path")
	require.NotEmpty(t, kubeconfigPath, "kubeconfig_path output must not be empty")

	kubectlOpts := k8s.NewKubectlOptions("", kubeconfigPath, "default")

	// ── Deploy nginx ────────────────────────────────────────────────────────
	defer k8s.KubectlDelete(t, kubectlOpts, "testdata/nginx.yaml")
	k8s.KubectlApply(t, kubectlOpts, "testdata/nginx.yaml")

	// ── Wait for pod ────────────────────────────────────────────────────────
	k8s.WaitUntilNumPodsCreated(t, kubectlOpts,
		metav1.ListOptions{LabelSelector: "app=nginx-e2e"},
		1, 30, 10*time.Second,
	)

	pods := k8s.ListPods(t, kubectlOpts, metav1.ListOptions{LabelSelector: "app=nginx-e2e"})
	require.NotEmpty(t, pods)
	k8s.WaitUntilPodAvailable(t, kubectlOpts, pods[0].Name, 30, 10*time.Second)

	// ── Wait for service ────────────────────────────────────────────────────
	k8s.WaitUntilServiceAvailable(t, kubectlOpts, "nginx-e2e", 20, 10*time.Second)
	svc := k8s.GetService(t, kubectlOpts, "nginx-e2e")
	endpoint := k8s.GetServiceEndpoint(t, kubectlOpts, svc, 80)

	// ── HTTP probe ──────────────────────────────────────────────────────────
	t.Run("nginx_returns_200", func(t *testing.T) {
		url := fmt.Sprintf("http://%s", endpoint)
		_, err := retry.DoWithRetryE(t, "HTTP probe to nginx", 10, 10*time.Second, func() (string, error) {
			resp, err := http.Get(url) //nolint:gosec // test code
			if err != nil {
				return "", err
			}
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusOK {
				return "", fmt.Errorf("got HTTP %d, want 200", resp.StatusCode)
			}
			logger.Log(t, fmt.Sprintf("nginx responded with HTTP %d ✓", resp.StatusCode))
			return "ok", nil
		})
		assert.NoError(t, err, "nginx must return HTTP 200")
	})
}
