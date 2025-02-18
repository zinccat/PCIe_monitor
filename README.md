# PCIe_monitor
Simple PCIe bandwidth monitor

```bash
nvcc -L/usr/lib -lnvidia-ml -lncurses monitor.cu -o monitor
./monitor
```

![](./demo.png)