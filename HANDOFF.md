# HANDOFF — note per il prossimo core (leggere per primo in ogni nuova chat!)

## 0. Contesto
- Repo collezione: `lroby74/Tangcores`. Ogni core = una cartella (`TangPong/` = riferimento funzionante).
- Target: Tang Console 138K (GW5AST-138), caricamento da microSD (`cores/nome.bin`), mai JTAG.
- Utente: builda su Windows + Gowin EDA Standard V1.9.12.04 (licenza attiva). Parla italiano.
- Agente: sandbox Linux SENZA Gowin — non può compilare, solo preparare codice + diagnosticare log.
- Firmware BL616: maggio 2025 = ultima esistente (repo fermo). IDs 1-6 (NES..PCXT).
- Licenza opere derivate da NESTang: **GPL-3.0 obbligatoria**. HDMI hdl-util = Apache-2.0.

## 1. Architettura di riferimento (copiare da TangPong/, non riscrivere!)
- `iosys_bl616` (UART 2Mbaud): param FREQ **deve** = clock reale (50M). CORE_ID ignoto è SICURO (forza riprogrammazione); mai spoofare ID noti.
- `usb_hid_host` vuole `usb_hid_host_rom.hex` reperibile al build (progetto root!). Senza, USB morto.
- `controller_ds2`: param FREQ = clock reale (50M). (HW DS2 non testato: adattatore utente rotto.)
- HDMI = hdl-util/hdmi (`hdmi2/`) + `set_option -verilog_std sysv2017` nel tcl. Senza sysv2017, centinaia di errori.
- PLL: copiare i defparam dal template (MDIV_SEL=18 per 12MHz da 50MHz!). Secondo clock = solo ODIVx+CLKOUTx_EN.
- File dati `$readmemb/$readmemh` cercati nella DIR DI BUILD (root progetto): vanno committati in root (la sim usa le sue copie via Makefile, non toccarla).
- `.cst`: nomi porte ESATTI del top (es. `ds_clk/ds_miso/ds_mosi/ds_cs`, non `ds2_*`!). Porte senza LOCATE = errori P&R.
- `.sdc`: `create_clock` sui net di top, `create_generated_clock` per divisori RTL (es. clk7m = /2 di clk14m).
- Porte `sim_*` solo dentro `ifdef VERILATOR`, con gestione virgole corretta (Gowin non definisce VERILATOR).

## 2. ERRORI GIÀ FATTI — non ripetere!
- **E1. `default_nettype none` lasciato aperto.** Gowin compila TUTTO in un'unità sola: un file che apre `none` senza richiuderlo avvelena tutti i successivi (155 errori EX3094!). REGOLA: ogni file con `none` deve finire con `` `default_nettype wire ``. Verilator NON lo becca (ordine file diverso).
- **E2. `;` dimenticati nei defparam** generati da script (logo!). Gowin: EX3863/EX2652 a cascata. Verificare output generatore == file.
- **E3. File dati mancanti in root** (`*.txt`, `*.hex`) → errori elaborazione. Vedi §1.
- **E4. Reset asincrono non canonico** → Gowin EX2452 è ERRORE (non warning!). Solo forma:
      always_ff @(posedge clk or negedge rstn) begin
          if (!rstn) ... else ...
      Mai ternary (`cond ? a : b`) come reset!
- **E5. Init alla dichiarazione sulle porte** (`output logic x = N`) → Gowin lo IGNORA (warning EX2478). Serve reset reale che copra il valore.
- **E6. Porte iosys scollegate** (`mgmt_*`, `kbd_*`, `fdd_*`) = NORMALE (NESTang fa uguale). Warning EX2565 innocui.
- **E7. Core senza ROM = menu firmware bloccato PER DISEGNO.** L'overlay si spegne solo caricando ROM o con combo OSD. Documentare nel README: **SELECT + D-PAD DESTRA** (bit7 = freccia, NON bumper! bumper+select = 0x808, ignorato). Match esatto, solo quei due tasti.
- **E8. Mai invertire `overlay` nel core**: rompe l'accoppiamento firmware (menu visibile ma non navigabile). Lasciare il segnale com'è.
- **E9. Cache browser sugli ZIP**: MAI riusare lo stesso nome file! `?v=` non basta (redirect GitHub cachato). Ogni revisione = nome unico (`Nome_fixN.zip`, poi `Nome_v1.0.zip`).
- **E10. Token agente limitato al repo di sessione**: push verso altri repo = 403. Repo nuovi = upload lato utente (web o bundle+git).
- **E11. Allegati chat NON arrivano alla sandbox.** Log via testo incollato o upload su branch via web.
- **E12. Batch shell con heredoc**: il newline dopo `EOF` rompe le catene `&&` (prosegue anche se fallisce!). Verificare SEMPRE ogni patch/commit/zip con grep prima di proseguire.

## 3. Workflow collaudato
- `buildall.bat` deve: `cd %~dp0`, controllo `build.tcl`, ricerca `gw_sh` (path noto + PATH + GOWIN_HOME + C:/D:), redirect puro CMD `> build.log 2>&1` (NO PowerShell!), stampa auto righe ERROR (`findstr /n /I "ERROR"`), `pause` su TUTTE le uscite, stampa `VERSION` (identifica lo screenshot!).
- File `VERSION` in root, bumpato a ogni giro (`fixN` → `v1.0` alla release).
- Ship: commit + push branch sessione, rigenera repo standalone + zip + bundle, verifica contenuto zip (fix dentro? niente zip-nello-zip? dimensioni sane?), link unico nuovo.
- Release pubblica: tag + `.bin` come asset (i giocatori non hanno Gowin). LICENSE root via template web GitHub.

## 4. Checklist nuovo core
1. Copia scheletro da TangPong/ (tcl/cst/sdc/bat/sim-structure), adatta il minimo.
2. Sim Verilator PASS (testbench dedicato).
3. Build utente → ciclo fix guidato da build.log (mai alla cieca!).
4. Test HW: video, controlli (tutti i tipi!), audio, reset, 2P se previsto.
5. Release: README standalone (con nota OSD se ROM-less!), ATTRIBUTION.md, VERSION v1.0, zip unico, tag + .bin.

## 5. ZX81 (prossimo core) — vincoli utente
- Caricamento nastro 1:1 a velocità originale (~300 baud), MAI accelerato.
- Espansione RAM 16KB sempre presente (molti giochi la richiedono).
- Sorgente: https://github.com/MiSTer-devel/ZX81_MiSTer (rtl/ + T80 + keyboard da tenere, sys/pll/top da sostituire; ROM caricata da SD, NON nel repo).
