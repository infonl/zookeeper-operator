/**
 * Copyright (c) 2018 Dell Inc., or its subsidiaries. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (&the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

package e2e

import (
	"context"
	"github.com/go-logr/logr"
	api "github.com/pravega/zookeeper-operator/api/v1beta1"
	zookeeperv1beta1 "github.com/pravega/zookeeper-operator/api/v1beta1"
	zookeepercontroller "github.com/pravega/zookeeper-operator/controllers"
	zk_e2eutil "github.com/pravega/zookeeper-operator/pkg/test/e2e/e2eutil"
	zkClient "github.com/pravega/zookeeper-operator/pkg/zk"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"os"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"testing"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var (
	cfg           *rest.Config
	k8sClient     client.Client // You'll be using this client in your tests.
	testEnv       *envtest.Environment
	ctx           context.Context
	cancel        context.CancelFunc
	testNamespace = "default"
	logger        logr.Logger
)

func TestAPIs(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Controller e2e Suite")
}

var _ = BeforeSuite(func() {
	logger = zap.New(zap.WriteTo(GinkgoWriter), zap.UseDevMode(true))
	logf.SetLogger(logger)

	ctx, cancel = context.WithCancel(context.TODO())

	enabled := true
	By("bootstrapping test environment")
	testEnv = &envtest.Environment{
		Config:             cfg,
		UseExistingCluster: &enabled,
	}

	/*
		Then, we start the envtest cluster.
	*/
	cfg, err := testEnv.Start()
	Expect(err).NotTo(HaveOccurred())
	Expect(cfg).NotTo(BeNil())

	err = zookeeperv1beta1.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())

	/*
		After the schemas, you will see the following marker.
		This marker is what allows new schemas to be added here automatically when a new API is added to the project.
	*/

	//+kubebuilder:scaffold:scheme

	/*
		A client is created for our test CRUD operations.
	*/
	k8sClient, err = client.New(cfg, client.Options{Scheme: scheme.Scheme})
	Expect(err).NotTo(HaveOccurred())
	Expect(k8sClient).NotTo(BeNil())

	if os.Getenv("RUN_LOCAL") == "true" {
		k8sManager, err := ctrl.NewManager(cfg, ctrl.Options{
			Scheme: scheme.Scheme,
			Cache:  cache.Options{Namespaces: []string{testNamespace}},
		})
		Expect(err).ToNot(HaveOccurred())

		err = (&zookeepercontroller.ZookeeperClusterReconciler{
			Client:   k8sManager.GetClient(),
			Scheme:   k8sManager.GetScheme(),
			ZkClient: new(zkClient.DefaultZookeeperClient),
		}).SetupWithManager(k8sManager)
		Expect(err).ToNot(HaveOccurred())

		go func() {
			defer GinkgoRecover()
			err = k8sManager.Start(ctrl.SetupSignalHandler())
			Expect(err).ToNot(HaveOccurred(), "failed to run manager")
		}()
	}

}, 60)

/*
Kubebuilder also generates boilerplate functions for cleaning up envtest and actually running your test files in your controllers/ directory.
You won't need to touch these.
*/

var _ = AfterSuite(func() {
	cancel()
	By("tearing down the test environment")
	err := testEnv.Stop()
	Expect(err).NotTo(HaveOccurred())
})

// Catches whatever a failed/timed-out spec's own cleanup never got to run
// (a spec that fails mid-test - e.g. a ReadyTimeout - never reaches its own
// trailing WaitForClusterToTerminate call). Waiting for full termination
// here, not just firing the Delete, matters specifically for that case: on
// a resource-constrained single-node cluster, letting the NEXT spec start
// creating a new multi-pod cluster while THIS one's pods/PVCs are still
// mid-teardown starves it of the same capacity, which was observed live to
// cascade into a run of several specs in a row never getting any pods
// scheduled at all (repeated "pods ([])" for the full ReadyTimeout).
var _ = AfterEach(func() {
	zkList := &api.ZookeeperClusterList{}
	listOptions := []client.ListOption{
		client.InNamespace(testNamespace),
	}
	Expect(k8sClient.List(ctx, zkList, listOptions...)).NotTo(HaveOccurred())
	for i := range zkList.Items {
		zk := &zkList.Items[i]
		Expect(k8sClient.Delete(ctx, zk)).NotTo(HaveOccurred())
		Expect(zk_e2eutil.WaitForClusterToTerminate(logger, k8sClient, zk)).NotTo(HaveOccurred())
	}
})
