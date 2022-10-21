// Copyright (c) 2021 Quark Container Authors / 2018 The gVisor Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use nix::mount::MsFlags;
use std::fs::create_dir_all;

use super::super::container::mounts::*;
use super::super::super::namespace::Util;
use super::super::super::qlib::common::*;
use super::super::super::qlib::path::{IsAbs, Join};
use super::super::oci::Spec;
use super::sandbox_process::*;

const DEFAULT_QUARK_SANDBOX_ROOT_PATH: &str = "/var/lib/quark/";

pub struct FsImageMounter {
    pub rootPath: String,
    pub sandboxId: String,
}

impl FsImageMounter {
    pub fn NewWithRootPath(sandboxId: &str, rootPath: &str) -> Self {
        return FsImageMounter {
            rootPath: rootPath.to_string(),
            sandboxId: sandboxId.to_string(),
        };
    }

    pub fn New(sandboxId: &str) -> Self {
        return FsImageMounter {
            rootPath: DEFAULT_QUARK_SANDBOX_ROOT_PATH.to_string(),
            sandboxId: sandboxId.to_string(),
        };
    }

    fn sandboxRoot(&self) -> String {
        return Join(&self.rootPath, &self.sandboxId);
    }

    // This method mount the fs image specified in spec into the quark sandbox path and made available to qkernel
    // TODO: still not sure if this will be observable from inside... Let's do it first
    pub fn MountContainerFs(&self, bundleDir: &str, spec: &Spec, containerId: &str) -> Result<()> {
        let rbindFlags = libc::MS_REC | libc::MS_BIND;
        let rootSpec = spec.root.path.as_str();
        let containerFsRootSource = if IsAbs(rootSpec) {
            rootSpec.to_string()
        } else {
            Join(bundleDir, rootSpec)
        };
        let containerFsRootTarget = Join(&self.sandboxRoot(), containerId);
        match create_dir_all(&containerFsRootTarget) {
            Ok(()) => (),
            Err(_e) => panic!(
                "failed to create dir to mount root for container {}",
                containerId
            ),
        };

        info!(
            "start subcontainer: mounting {} to {}",
            &containerFsRootSource, &containerFsRootTarget
        );
        let ret = Util::Mount(
            &containerFsRootSource,
            &containerFsRootTarget,
            "",
            rbindFlags,
            "",
        );
        if ret < 0 {
            panic!(
                "MountContainerFs: mount container rootfs fail, error is {}",
                ret
            );
        }

        let linux = spec.linux.as_ref().unwrap();
        for m in &spec.mounts {
            // TODO: check for nasty destinations involving symlinks and illegal
            //       locations.
            // NOTE: this strictly is less permissive than runc, which allows ..
            //       as long as the resulting path remains in the rootfs. There
            //       is no good reason to allow this so we just forbid it
            if !m.destination.starts_with('/') || m.destination.contains("..") {
                let msg = format!("invalid mount destination: {}", m.destination);
                return Err(Error::Common(msg));
            }
            let (flags, data) = parse_mount(m);
            if m.typ == "cgroup" {
                //mount_cgroups(m, rootfs, flags, &data, &linux.mount_label, cpath)?;
                // won't mount cgroup
                continue;
            } else if m.destination == "/dev" {
                // dev can't be read only yet because we have to mount devices
                MountFrom(
                    m,
                    &self.sandboxRoot(),
                    flags & !MsFlags::MS_RDONLY,
                    &data,
                    &linux.mount_label,
                )?;
            } else {
                MountFrom(m, &self.sandboxRoot(), flags, &data, &linux.mount_label)?;
            }
        }
        
        return Ok(());
    }
}
