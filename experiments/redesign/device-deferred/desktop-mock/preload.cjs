// No generic IPC, shell, filesystem or authority-bearing bridge.
const {contextBridge}=require('electron');
contextBridge.exposeInMainWorld('muyonLab',Object.freeze({mode:'mock',contract:'provisional',nativeCore:'NOT_CONNECTED'}));
