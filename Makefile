# Export fabrication and assembly files for JLCPCB.
#
#     make            gerbers + drill + zip + BOM + CPL + PDFs
#     make fab        just the gerber/drill zip (bare PCB order)
#     make pdf        schematic and board drawings
#     make check      ERC + DRC, non-zero exit on violations
#     make clean      remove build/

PROJECT   := ez-uart-adapter
BUILD     := build
GERBERDIR := $(BUILD)/gerbers

KICAD_CLI ?= $(shell command -v kicad-cli 2>/dev/null || \
	echo /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli)

# GNU sed's -i takes no argument; BSD/macOS sed requires an (empty) one.
SED_I := $(shell sed --version >/dev/null 2>&1 && echo -i || echo "-i ''")

PCB := $(PROJECT).kicad_pcb
SCH := $(PROJECT).kicad_sch

# Paste layers are not needed to fabricate a bare board, but JLCPCB's own
# KiCad guide includes them and their viewer copes fine.
LAYERS := F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts

# One page per layer in the board PDF. Edge.Cuts is drawn on every page so
# each sheet is readable on its own.
PDFLAYERS := F.Cu,B.Cu,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,F.Fab,B.Fab,Edge.Cuts

ZIP    := $(BUILD)/$(PROJECT)-gerbers.zip
BOM    := $(BUILD)/$(PROJECT)-bom.csv
CPL    := $(BUILD)/$(PROJECT)-cpl.csv
SCHPDF := $(BUILD)/$(PROJECT)-schematic.pdf
PCBPDF := $(BUILD)/$(PROJECT)-pcb.pdf

.PHONY: all fab pdf check erc drc clean

all: fab $(BOM) $(CPL) pdf

fab: $(ZIP)

pdf: $(SCHPDF) $(PCBPDF)

# Protel extensions (.GTL/.GBL/...) are KiCad's default and are what JLCPCB
# expects, so --no-protel-ext is deliberately absent. --check-zones refills
# the zones during the plot so a stale fill can never be shipped.
$(GERBERDIR): $(PCB)
	@mkdir -p $(GERBERDIR)
	$(KICAD_CLI) pcb export gerbers \
		--output $(GERBERDIR) \
		--layers "$(LAYERS)" \
		--no-x2 \
		--check-zones \
		$(PCB)
	$(KICAD_CLI) pcb export drill \
		--output $(GERBERDIR) \
		--format excellon \
		--drill-origin absolute \
		--excellon-units mm \
		--excellon-separate-th \
		$(PCB)
	@touch $(GERBERDIR)

$(ZIP): $(GERBERDIR)
	@rm -f $(ZIP)
	cd $(GERBERDIR) && zip -q -r ../$(notdir $(ZIP)) .
	@echo "==> $(ZIP)"

# JLCPCB matches parts on the LCSC column; Value/Footprint are only there for
# human review. Ranges are disabled so designators come out as C1,C2,C3
# rather than C1-C3, which JLCPCB's parser prefers.
$(BOM): $(SCH)
	@mkdir -p $(BUILD)
	$(KICAD_CLI) sch export bom \
		--output $(BOM) \
		--fields 'Reference,Value,Footprint,LCSC Part' \
		--labels 'Designator,Comment,Footprint,LCSC Part #' \
		--group-by 'Value,Footprint,LCSC Part' \
		--ref-range-delimiter '' \
		--exclude-dnp \
		$(SCH)
	@echo "==> $(BOM)"

# Absolute origin, matching --drill-origin absolute above. The header rewrite
# saves mapping the columns by hand in JLCPCB's upload dialog; extra columns
# are ignored on their side.
$(CPL): $(PCB)
	@mkdir -p $(BUILD)
	$(KICAD_CLI) pcb export pos \
		--output $(CPL) \
		--format csv \
		--units mm \
		--side both \
		--exclude-dnp \
		$(PCB)
	@sed $(SED_I) -e '1s/^Ref,/Designator,/' -e '1s/,PosX,/,Mid X,/' \
		-e '1s/,PosY,/,Mid Y,/' -e '1s/,Rot,/,Rotation,/' \
		-e '1s/,Side$$/,Layer/' $(CPL)
	@echo "==> $(CPL)"

$(SCHPDF): $(SCH)
	@mkdir -p $(BUILD)
	$(KICAD_CLI) sch export pdf --output $(SCHPDF) $(SCH)
	@echo "==> $(SCHPDF)"

$(PCBPDF): $(PCB)
	@mkdir -p $(BUILD)
	$(KICAD_CLI) pcb export pdf \
		--output $(PCBPDF) \
		--layers "$(PDFLAYERS)" \
		--common-layers Edge.Cuts \
		--mode-multipage \
		--include-border-title \
		--check-zones \
		$(PCB)
	@echo "==> $(PCBPDF)"

check: erc drc

erc:
	$(KICAD_CLI) sch erc --exit-code-violations $(SCH)

drc:
	$(KICAD_CLI) pcb drc --exit-code-violations --refill-zones $(PCB)

clean:
	rm -rf $(BUILD)
