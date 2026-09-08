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
	"fmt"
	"github.com/go-logr/logr"
	api "github.com/pravega/zookeeper-operator/api/v1beta1"
	zookeeperv1beta1 "github.com/pravega/zookeeper-operator/api/v1beta1"
	zookeepercontroller "github.com/pravega/zookeeper-operator/controllers"
	zk_e2eutil "github.com/pravega/zookeeper-operator/pkg/test/e2e/e2eutil"
	zkClient "github.com/pravega/zookeeper-operator/pkg/zk"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/kubernetes"
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
	// Plain clientset alongside k8sClient - controller-runtime's client.Client
	// has no logs API, and dumpPodLogs below needs one to catch a container
	// crashing on this specific runner (see AfterEach) before AfterEach's own
	// cleanup deletes the pod out from under a Makefile-level diagnostics dump.
	clientset     *kubernetes.Clientset
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

	clientset, err = kubernetes.NewForConfig(cfg)
	Expect(err).NotTo(HaveOccurred())

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
	// On failure, grab every leftover cluster's pod logs before the delete
	// below removes them for good - a live cluster only retains Events (no
	// exit reason/stack trace) once a Pod object is gone, which is all a
	// Makefile-level `kubectl describe` after go test returns could ever see.
	// Confirmed live this matters: a CI run's Events showed zookeeper-0
	// pulling its image 4 times, being (re)started, then "Back-off
	// restarting failed container" - a real crash, not the image-pull/
	// scheduling/resource-starvation theories chased before this - but with
	// nothing there saying *why* it crashed.
	if CurrentGinkgoTestDescription().Failed {
		dumpPodLogs()
	}

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

func dumpPodLogs() {
	podList := &corev1.PodList{}
	if err := k8sClient.List(ctx, podList, client.InNamespace(testNamespace)); err != nil {
		logger.Info(fmt.Sprintf("dumpPodLogs: failed to list pods: %v", err))
		return
	}
	for i := range podList.Items {
		pod := &podList.Items[i]
		for _, c := range pod.Spec.Containers {
			// Previous first - the pod may already be on its Nth restart by
			// the time a ReadyTimeout fires, and the *previous* container's
			// exit is almost always the one still explaining the failure
			// (the current attempt may just be mid-backoff with no output
			// yet). Fall back to the current/only container if there is no
			// previous one (e.g. a first-attempt CrashLoopBackOff, or
			// FailedScheduling with no container ever having run).
			raw, err := clientset.CoreV1().Pods(pod.Namespace).GetLogs(pod.Name, &corev1.PodLogOptions{
				Container: c.Name,
				Previous:  true,
				TailLines: int64Ptr(200),
			}).DoRaw(ctx)
			if err != nil {
				raw, err = clientset.CoreV1().Pods(pod.Namespace).GetLogs(pod.Name, &corev1.PodLogOptions{
					Container: c.Name,
					TailLines: int64Ptr(200),
				}).DoRaw(ctx)
			}
			if err != nil {
				logger.Info(fmt.Sprintf("dumpPodLogs: %s/%s: no logs available: %v", pod.Name, c.Name, err))
				continue
			}
			fmt.Fprintf(GinkgoWriter, "\n----- logs: pod=%s container=%s -----\n%s\n----- end logs: pod=%s container=%s -----\n",
				pod.Name, c.Name, string(raw), pod.Name, c.Name)
		}
	}
}

func int64Ptr(v int64) *int64 { return &v }
