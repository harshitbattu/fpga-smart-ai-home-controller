# FPGA Smart AI Home Controller (Nexys 4 DDR, Vivado 2024.2)

## Folder contents
| Folder / file | What it is |
|---|---|
| `rtl/` | 18 Verilog modules + include files (`home_defs.vh`, `bcd_func.vh`, `msg_rom.vh`, `nn_weights.vh`) |
| `ai/` | Neural-network training (`train_nn.py`), UCI Occupancy dataset, test vectors, results |
| `tb/` | Testbenches: `tb_smart_home.v` (101 system checks), `tb_units_realtime.v` (9 real-rate checks), `tb_nn_engine.v` (12 417-sample AI test), `tb_gas_latency.v`, `adt7420_model.v` |
| `constr/nexys4ddr_smart_home.xdc` | Pin constraints (from Digilent's official master XDC) |
| `create_project.tcl` | Creates the whole Vivado project in one step |
| `tools/` | `home_console.py` (PC terminal), `ai_demo.py` (streams real data to the board, measures AI accuracy), `gen_msg_rom.py`, `plot_waves.py`, `ai_figs.py` |
| `sim/` | Simulation logs from the verification runs |
| `docs/` | Report (.docx/.pdf), figures |

## Build in Vivado 2024.2
1. Open Vivado → Tcl Console:
   ```
   cd C:/path/to/fpga_home
   source create_project.tcl
   build_all
   ```
2. Reports are written to `reports/` (utilization, timing, power). Take screenshots for Chapter 5.4.
3. Hardware Manager → Open Target → Program Device → `vivado/smart_home.runs/impl_1/smart_home_top.bit`.

## Simulate in Vivado
Flow Navigator → Run Simulation → Run Behavioral Simulation (top = `tb_smart_home`).
Tcl console prints each PASS/FAIL and `ALL TESTS PASSED` at the end (about 23 ms of simulated time;
may take a few minutes). For the real-rate tests set the simulation top to `tb_units_realtime`.

## Use
Terminal: 115200 baud, 8-N-1, enable local echo. Commands: `STATUS`, `MODE AUTO|MANUAL`, `FAN n`, `LIGHT ON|OFF`,
`TH n`, `OCC n`, `ECO 0|1`, `ARM pppp`, `DISARM pppp`, `PIN old new`, `ACK`, `TIME hh mm`, `FAST 0|1`,
`PROFILE`, `CLEAR`, `ENERGY`, `AI t rh lux co2` (neural-network classification), `ENV rh lux co2` (live AI mode). Default PIN: 1234.

Switches: SW0 motion, SW1 dark, SW2 gas, SW3 door, SW12 fast time, SW13 mute, SW14 use Pmod JA sensors.
Buttons: BTNC arm, BTNU/BTND threshold, BTNL display page, BTNR acknowledge, CPU_RESET reset.

## AI (neural network)
* Retrain / re-export: `cd ai && python3 train_nn.py` (needs numpy, scikit-learn). Regenerates `rtl/nn_weights.vh` and `ai/nn_test_vectors.mem`.
* Hardware accuracy test in Vivado: set simulation top to `tb_nn_engine` and run (prints bit-exact count and accuracy).
* On the board: `python tools/ai_demo.py COM5 500` streams 500 real test samples and prints the accuracy measured on the FPGA.
