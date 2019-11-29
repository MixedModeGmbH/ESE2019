# Portable TrustZone-Apps mit OP-TEE

## Hintergrund und Einstieg in Entwicklung und Prototyping mit QEMU

<!-- markdownlint-disable MD033 img -->
[<img align="right" src="3rd-party/ESE_Banner_2019_Referent.png">](https://ese-kongress.de/)
<!-- markdownlint-enable MD033 -->

Ergänzendes Material zum Vortrag auf dem Embedded Software Engineering Kongress, vom 2. bis 6. Dezember 2019 in Sindelfingen.

## Vorbemerkung

Für die Installation wird mindestens 20GB freier Festplattenplatz benötigt.

## Einrichten der Entwicklungsumgebung

Es gibt verschiedene Möglichkeiten, die Entwicklungsumgebung für erste Gehversuche einzurichten.

**Nix-Shell**  
Empfehlenswert ist die Verwendung des Nix Paketmanagers. Abhängigkeiten werden getrennt vom System verwaltet, was Nebenwirkungen minimiert. Gleichzeitig steht die gewohnte Arbeitsumgebung zur Verfügung, ohne dass erst aufwändig Ordnerfreigaben für eine VM eingerichtet werden müssten.
Zu guter letzt erhält man ein reproduzierbares Setup, (nahezu) unabhängig vom darunterliegenden Linux-System.

**Virtuelle Maschine**  
Die Einrichtung einer Virtuellen Maschine bedeutet den größten Aufwand, minimiert aber der Einfluss auf das eigene System.  
Unter Windows ist dies die empfohlene Methode.

**direkte Installation**  
Bei der direlten Installation aller Abhängigkeiten unter Linux ist eine rückstandslose Entfernung der installierten Software aufwändig. Dafür ist die gewohne Arbeitsumgebung (Code-Editor etc.) verfügbar.  
Ein Metapaket (für Ubuntu) zur einfacheren Verwaltung der Abhängigkeiten steht im Repository bereit.

### Nix-Shell

#### Installieren des Nix Paketmanagers

Der Nix Paketmanager benötigt sudo-Rechte einzig zur Erstellung des Verzeichnisses '/nix'. Diese werden erst bei Bedarf angefordert.

```bash
# KEIN sudo!
curl https://nixos.org/nix/install | sh
```

Installation von Nix mit Signaturprüfung (und Hinweise zur Deinstallation): <https://nixos.org/nix/download.html>

#### Einrichten der Umgebung

Falls noch nie mit Git gearbeitet wurde, Git installieren und konfigurieren:

```bash
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

```bash
git clone --depth 1 https://github.com/MixedModeGmbH/ESE2019
cd ESE2019
nix-shell --pure
```

Der erste Aufruf von `nix-shell` lädt alle benötigten Abhängigkeiten und richtet diese ein. Je nach System und verfügbarer Bandbreite kann dies mehrere Stunden dauern.

### VM

Die Erstellung einer VM ist an anderer Stelle ausreichend dokumentiert. Die wesentlichen Schritte (z.B. mit VirtualBox) sind:

1. Installationsmedium laden (Ubuntu 18.04 LTS (Bionic)):
 <http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-amd64/current/images/netboot/mini.iso>
2. Neue VM erstellen (64bit Ubuntu/Linux-Guest, 2cores, 2Gig RAM, 64Gig HD)
3. Installation mit geladenen `mini.iso` starten. Empfohlene Paketauswahl via `tasksel`: *minimal Lubuntu* und *OpenSSH server*
4. Terminal starten und
  
    ```bash
    sudo apt update
    sudo apt upgrade
    sudo apt install gcc make perl ccache
    ```

5. installiere VBoxGuestAddons:

    ```bash
    cd /media/mm/VBox_GAs_<Tab>
    sudo ./VBoxLinuxAdditions.run
    reboot
    ```

danach weiter wie direkte Installation (oder mit Nix-Shell).

### direkte Installation

(getestest mit Ubuntu 18.04 LTS in VirtualBox)

1. Installieren benötigter Pakete (nur dieser Schritt benötigt sudo-Rechte)

    ```bash
    wget https://raw.githubusercontent.com/MixedModeGmbH/ESE2019/master/optee-devel-deps-ese2019_1.0.0_all.deb
    sudo apt install ./optee-devel-deps-ese2019_1.0.0_all.deb
    ```

2. Git konfigurieren

    ```bash
    git config --global user.email "you@example.com"
    git config --global user.name "Your Name"
    ```

3. Manifest und Quellen laden

    ```bash
    mkdir -p ~/optee-qemu
    cd ~/optee-qemu
    repo init -u https://github.com/OP-TEE/manifest.git -m default.xml -b 3.6.0
    repo sync
    ```

4. Cross-Compile toolchains laden

    ```bash
    cd ./build
    make toolchains -j3
    cd ..
    ```

5. Buildroot laden und alle Komponenten kompilieren

    ```bash
    mkdir ./qemu-share
    export QEMU_VIRTFS_ENABLE=y
    export QEMU_VIRTFS_HOST_DIR="$(pwd)/qemu-share"
    export QEMU_USERNET_ENABLE=y

    cd build
    make -j1 all
    ```

    Je nach System und verfügbarer Bandbreite kann dies mehrere Stunden dauern.

## Übersetzen und Ausführen des TA-Beispiels

Zur Übung wird Empfohlen, die Schritte aus dem Artikel im Kongressband nachzuvollziehen.  
Zur Kontrolle bzw. falls der Kongressband nicht greifbar ist, sind die einzelnen Schritte auch in zwei Patchfiles zusammengefasst:

* `01-hello-world-to-template.patch`  
Dieser Patch beinhaltet alle Schritte um aus dem `hello_world`-Beispiel eine Vorlage für eine neue TA zu generieren.

* `02-template-to-pincheck.patch`
Dieser Patch beinhaltet alle Schritte um aus dem generierten Template die verwendete Beispiel-TA zu generieren.

* `rebuildfrompatches.sh`  
Dieses Skript lädt das `hello_world`-Beispiel von GitHub und wendet die Patchfiles darauf an. Für das Ergebnis wird ein neues Verzeichnis unterhalb von `/tmp` angelegt.

Das resultierende Beispiel muss nicht zwingen wie im Artikel beschrieben in das `optee_example` repository integriert werden. Es kann auch in den geteilten Ordner `qemu-share` verschoben und in einer Nix-Shell mittels `makeapp.sh` compiliert werden. Auf diese Weise können Änderungen ohne Neustart des Emulators getestet werden. Die Datei `qemu-copy-paste.txt` gibt Hinweise zu den dafür im Emulator benötigten Befehlen.
