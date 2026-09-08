/**
 * Copyright (c) 2018 Dell Inc., or its subsidiaries. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

package e2eutil

import (
	api "github.com/pravega/zookeeper-operator/api/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// NewDefaultCluster returns a cluster with an empty spec, which will be filled
// with default values
func NewDefaultCluster(namespace string) *api.ZookeeperCluster {
	return &api.ZookeeperCluster{
		TypeMeta: metav1.TypeMeta{
			Kind:       "ZookeeperCluster",
			APIVersion: "zookeeper.pravega.io/v1beta1",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:      "zookeeper",
			Namespace: namespace,
		},
		Spec: api.ZookeeperClusterSpec{
			// Pinned explicitly, NOT left to WithDefaults()'s own
			// DefaultZkContainerRepository/Version fallback: that default now
			// points at ghcr.io/infonl/zookeeper, this fork's own CVE-remediated
			// image, which doesn't exist yet - it's only published once a real
			// release actually runs the new `make push` GHCR pipeline (see
			// .github/workflows/ci.yaml's publish job). Every spec that doesn't
			// override Spec.Image (5 of 8 - upgrade_test.go, multiple_zk_test.go
			// and image_pullsecret_test.go already set their own explicitly)
			// goes through this constructor, so pointing it at a not-yet-published
			// image would ImagePullBackOff the whole suite. Remove this override
			// once ghcr.io/infonl/zookeeper:0.2.15-cve.1 is real and the E2E suite
			// should start exercising the actual product default too.
			Image: api.ContainerImage{
				Repository: "pravega/zookeeper",
				Tag:        "0.2.15",
			},
		},
	}
}

func NewClusterWithVersion(namespace, version string) *api.ZookeeperCluster {
	cluster := NewDefaultCluster(namespace)
	// Overwrite only the tag - reusing NewDefaultCluster's own pinned Image
	// (see its comment) rather than replacing the whole Spec, so this also
	// stays off the not-yet-published DefaultZkContainerRepository default.
	cluster.Spec.Image.Tag = version
	return cluster
}

func NewClusterWithEmptyDir(namespace string) *api.ZookeeperCluster {
	cluster := NewDefaultCluster(namespace)
	// Add StorageType without discarding NewDefaultCluster's pinned Image -
	// a wholesale `cluster.Spec = ZookeeperClusterSpec{...}` here previously
	// dropped it back to the WithDefaults() fallback, same reasoning as
	// NewClusterWithVersion above.
	cluster.Spec.StorageType = "ephemeral"
	return cluster
}
