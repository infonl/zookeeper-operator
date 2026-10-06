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
			// Pinned to this fork's last *published* ZooKeeper image rather than
			// WithDefaults()' DefaultZkContainerVersion: the default names the
			// release this commit becomes, whose image only exists after the
			// publish job of that release has run. Bump with each release.
			// (upgrade_test.go, multiple_zk_test.go and image_pullsecret_test.go
			// set their own images.)
			Image: api.ContainerImage{
				Repository: "ghcr.io/infonl/zookeeper",
				Tag:        "0.2.16-rc.2",
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
