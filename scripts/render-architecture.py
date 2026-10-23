#!/usr/bin/env python3
"""Render AWS diagrams with short English names and component numbers."""

from html import escape
from base64 import b64encode
from pathlib import Path
from urllib.parse import quote
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "docs/images"
STEM = "openstudy-duckdns-deployment-numbered"
INK, MUTED, ORANGE, PURPLE = "#232F3E", "#54616E", "#ED7100", "#8C4FFF"
SANS = "Arial, 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif"


class Diagram:
    def __init__(self):
        self.zones, self.edges, self.items = [], [], []
        self.boxes = {}

    def box(self, name, x, y, width, height, *, parent="1", stroke=INK, fill="#FFFFFF", dash="", layer="zones"):
        item = dict(kind="box", name=name, x=x, y=y, width=width, height=height,
                    parent=parent, stroke=stroke, fill=fill, dash=dash)
        self.boxes[name] = item
        getattr(self, layer).append(item)

    def icon(self, name, asset, x, y, size=64, parent="1"):
        source = IMAGES / "icons" / (asset if Path(asset).suffix else f"{asset}.svg")
        uri = ("data:image/png;base64," + b64encode(source.read_bytes()).decode()
               if source.suffix == ".png" else "data:image/svg+xml," + quote(source.read_text(), safe=""))
        item = dict(kind="icon", name=name, uri=uri, x=x, y=y, width=size, height=size, parent=parent)
        self.items.append(item)
        self.boxes[name] = item

    def edge(self, name, source, target, start, end, path, points=(), kind="normal"):
        self.edges.append(dict(name=name, source=source, target=target, start=start, end=end,
                               path=path, points=points, kind=kind))

    def label(self, name, value, x, y, width, *, parent="1", size=16, align="center"):
        if not value.isascii() or "\n" in value or len(value) > 32:
            raise ValueError("Diagram labels must be short English names and numbers.")
        self.items.append(dict(kind="label", name=name, value=value, x=x, y=y,
                               width=width, height=24, parent=parent, size=size, align=align))

    def marker(self, value, x, y, *, parent="1"):
        self.items.append(dict(kind="marker", name="number-" + value, value=value,
                               x=x, y=y, width=20, height=20, parent=parent))

    def svg(self):
        slug = STEM
        parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 1120" role="img" aria-labelledby="{slug}-title {slug}-desc">',
                 f'<title id="{slug}-title">OpenStudy AWS 아키텍처</title>',
                 f'<desc id="{slug}-desc">GitHub 배포 경로와 AWS 서울 리전의 EC2, 같은 ECS Task 안의 Gateway와 Service 두 컨테이너, RDS Primary 한 대를 표시하고 보조 AZ는 생략한 구성도다.</desc>',
                 '<defs>']
        for name, color in [("normal", MUTED), ("web", ORANGE), ("optional", MUTED), ("control", MUTED)]:
            parts.append(f'<marker id="{slug}-{name}" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto" markerUnits="userSpaceOnUse"><path d="M0 0L10 5L0 10Z" fill="{color}"/></marker>')
        parts.extend(['</defs>', '<rect width="1600" height="1120" fill="#FFFFFF"/>'])
        for item in self.zones:
            parts.append(self.svg_item(item))
        for edge in self.edges:
            color = ORANGE if edge["kind"] == "web" else MUTED
            dash = {"control": ' stroke-dasharray="3 7"', "optional": ' stroke-dasharray="9 7"'}.get(edge["kind"], "")
            parts.append(f'<path id="{edge["name"]}" d="{edge["path"]}" fill="none" stroke="{color}" stroke-width="2.4"{dash} marker-end="url(#{slug}-{edge["kind"]})"/>')
        for item in self.items:
            parts.append(self.svg_item(item))
        parts.append('</svg>')
        return '\n'.join(parts)

    @staticmethod
    def svg_item(item):
        kind, x, y, w, h = (item[k] for k in ["kind", "x", "y", "width", "height"])
        if kind == "box":
            dash = f' stroke-dasharray="{item["dash"]}"' if item["dash"] else ""
            return f'<rect id="{item["name"]}" x="{x}" y="{y}" width="{w}" height="{h}" fill="{item["fill"]}" stroke="{item["stroke"]}" stroke-width="2"{dash}/>'
        if kind == "icon":
            return f'<image id="{item["name"]}" x="{x}" y="{y}" width="{w}" height="{h}" href="{item["uri"]}"/>'
        if kind == "label":
            centered = item["align"] == "center"
            tx = x + w / 2 if centered else x
            return f'<text id="{item["name"]}" x="{tx}" y="{y+h/2}" dominant-baseline="central" text-anchor="{"middle" if centered else "start"}" font-family="Arial, sans-serif" font-size="{item["size"]}" font-weight="600" fill="{INK}">{escape(item["value"])}</text>'
        if kind == "marker":
            size = 9 if len(item["value"]) > 2 else 10
            return f'<g id="{item["name"]}"><circle cx="{x+10}" cy="{y+10}" r="9.5" fill="#FFFFFF" stroke="{INK}" stroke-width="1"/><text x="{x+10}" y="{y+10}" dominant-baseline="central" text-anchor="middle" font-family="Arial, sans-serif" font-size="{size}" font-weight="600" fill="{INK}">{escape(item["value"])}</text></g>'
        raise ValueError(f"Unsupported diagram item: {kind}")

    def drawio(self):
        doc = ET.Element("mxfile", host="app.diagrams.net", agent="OpenStudy-Infra", type="device", compressed="false")
        page = ET.SubElement(doc, "diagram", id="openstudy-aws-placement", name="OpenStudy AWS 아키텍처")
        model = ET.SubElement(page, "mxGraphModel", dx="1600", dy="1120", grid="1", gridSize="4", page="1", pageWidth="1600", pageHeight="1120", background="#FFFFFF", shadow="0")
        root = ET.SubElement(model, "root")
        ET.SubElement(root, "mxCell", id="0")
        ET.SubElement(root, "mxCell", id="1", parent="0")
        for item in self.zones + self.items:
            kind = item["kind"]
            base = "html=0;whiteSpace=wrap;rounded=0;shadow=0;"
            if kind == "box":
                style = base + f'shape=rectangle;container=1;collapsible=0;recursiveResize=0;strokeColor={item["stroke"]};fillColor={item["fill"]};strokeWidth=2;'
                if item["dash"]:
                    style += "dashed=1;dashPattern=" + item["dash"] + ";"
            elif kind == "icon":
                style = base + "shape=image;imageAspect=1;aspect=fixed;strokeColor=none;image=" + item["uri"] + ";"
            elif kind == "label":
                style = base + f'shape=text;strokeColor=none;fillColor=none;fontColor={INK};fontFamily=Arial;fontSize={item["size"]};fontStyle=1;align={item["align"]};verticalAlign=middle;spacing=0;'
            elif kind == "marker":
                size = 9 if len(item["value"]) > 2 else 10
                style = base + f'shape=ellipse;aspect=fixed;strokeColor={INK};fillColor=#FFFFFF;strokeWidth=1;fontColor={INK};fontFamily=Arial;fontSize={size};fontStyle=1;align=center;verticalAlign=middle;spacing=0;'
            else:
                raise ValueError(f"Unsupported diagram item: {kind}")
            cell = ET.SubElement(root, "mxCell", id=item["name"], value=item.get("value", ""), style=style, vertex="1", parent=item["parent"])
            parent = self.boxes.get(item["parent"], {"x": 0, "y": 0})
            ET.SubElement(cell, "mxGeometry", x=str(item["x"]-parent["x"]), y=str(item["y"]-parent["y"]), width=str(item["width"]), height=str(item["height"]), attrib={"as": "geometry"})
        for edge in self.edges:
            color = ORANGE if edge["kind"] == "web" else MUTED
            source, target = self.boxes[edge["source"]], self.boxes[edge["target"]]
            sx, sy = edge["start"]
            tx, ty = edge["end"]
            style = f'edgeStyle=orthogonalEdgeStyle;rounded=1;arcSize=8;jumpStyle=arc;jumpSize=8;endArrow=block;endFill=1;strokeColor={color};strokeWidth=2.4;exitX={(sx-source["x"])/source["width"]};exitY={(sy-source["y"])/source["height"]};entryX={(tx-target["x"])/target["width"]};entryY={(ty-target["y"])/target["height"]};exitPerimeter=0;entryPerimeter=0;'
            if edge["kind"] in {"optional", "control"}:
                style += "dashed=1;dashPattern=" + ("9 7" if edge["kind"] == "optional" else "3 7") + ";"
            cell = ET.SubElement(root, "mxCell", id=edge["name"], style=style, edge="1", parent="1", source=edge["source"], target=edge["target"])
            geometry = ET.SubElement(cell, "mxGeometry", relative="1", attrib={"as": "geometry"})
            if edge["points"]:
                points = ET.SubElement(geometry, "Array", attrib={"as": "points"})
                for x,y in edge["points"]:
                    ET.SubElement(points, "mxPoint", x=str(x), y=str(y))
        ET.indent(doc, space="  ")
        return ET.tostring(doc, encoding="unicode", xml_declaration=True)


def main():
    d = Diagram()
    d.box("aws",304,80,1248,968)
    d.box("region",344,160,1168,864,parent="aws",fill="#FDFDFD")
    d.box("vpc",384,512,1088,488,parent="region",stroke=PURPLE,fill="#FDFCFF")
    d.box("az-a",408,568,1040,408,parent="vpc",stroke="#879196",dash="6 5")
    d.box("public",432,616,664,336,parent="az-a",stroke="#7AA116",fill="#FAFDF6")
    d.box("private-a",1120,616,304,336,parent="az-a",stroke="#147EBA",fill="#F6FBFD")
    for name,x,w in [("management",432,192),("artifacts",648,192),("platform",864,192),("schedule",1080,192),("secret",1296,160)]:
        d.box(name,x,272,w,168,parent="region",stroke="#D5DBDB")
    d.box("github",48,64,208,144)
    d.box("terraform",48,264,208,144)
    d.box("dns",48,480,208,144)
    d.box("browser",48,776,208,144)
    d.box("ec2",448,680,632,248,parent="public",stroke=ORANGE)
    d.box("nginx",464,712,160,72,parent="ec2",stroke="#879196")
    d.box("task",456,812,616,112,parent="ec2",stroke=ORANGE,dash="9 7")
    d.box("gateway",472,848,248,64,parent="task",stroke=ORANGE,dash="9 7")
    d.box("service",752,848,304,64,parent="task",stroke=ORANGE,dash="9 7")
    d.box("rds",1140,680,264,248,parent="private-a",stroke="#147EBA")
    d.icon("aws-mark","aws",1464,96,56,"aws")
    d.icon("vpc-mark","vpc",400,524,32,"vpc")
    d.icon("github-mark","github.png",120,84,64,"github")
    d.icon("terraform-mark","terraform",120,288,64,"terraform")
    d.icon("dns-mark","duckdns.png",120,504,64,"dns")
    d.icon("browser-mark","browser",120,800,64,"browser")
    for name,asset,x,parent in [
        ("ssm","ssm",448,"management"),("parameter","parameter",540,"management"),
        ("s3-frontend","s3",664,"artifacts"),("s3-sql","s3",756,"artifacts"),
        ("ecs","ecs",880,"platform"),("ecr","ecr",972,"platform"),
        ("scheduler","scheduler",1096,"schedule"),("lambda","lambda",1188,"schedule"),
        ("secret","secrets",1344,"secret"),
    ]:
        d.icon(name+"-mark",asset,x,320,48,parent)
    d.icon("igw-mark","igw",352,736,64,"vpc")
    d.icon("public-mark","public-subnet",448,624,32,"public")
    d.icon("private-a-mark","private-subnet",1136,624,32,"private-a")
    d.icon("ec2-mark","ec2",720,712,64,"ec2")
    d.icon("ebs-mark","ebs",944,712,64,"ec2")
    d.icon("rds-mark","rds",1240,744,64,"rds")
    d.icon("nginx-mark","container",476,732,32,"nginx")
    d.icon("task-mark","task",472,816,24,"task")
    d.icon("gateway-mark","container",488,860,40,"gateway")
    d.icon("service-mark","container",768,860,40,"service")
    d.label("aws-label","AWS Cloud",328,104,400,parent="aws",size=20,align="left")
    d.label("region-label","Region",408,180,400,parent="region",size=20,align="left")
    d.label("vpc-label","VPC",488,528,280,parent="vpc",size=18,align="left")
    d.label("az-a-label","AZ",424,576,400,parent="az-a",align="left")
    d.label("public-label","Public Subnet",516,632,552,parent="public",align="left")
    d.label("private-a-label","Private Subnet",1192,632,208,parent="private-a",align="left")
    for name,value,y in [("github","GitHub",168),("terraform","Terraform",368),("dns","DuckDNS",584),("browser","Browser",880)]:
        d.label(name+"-label",value,64,y,176,parent=name)
    for name,value,x,w,parent in [
        ("ssm","SSM",436,80,"management"),("parameter","Parameter Store",524,96,"management"),
        ("s3-frontend","S3 Web",652,80,"artifacts"),("s3-sql","S3 SQL",744,96,"artifacts"),
        ("ecs","ECS",868,80,"platform"),("ecr","ECR",960,96,"platform"),
        ("scheduler","Scheduler",1084,80,"schedule"),("lambda","Lambda",1176,96,"schedule"),
        ("secret","Secrets Manager",1304,144,"secret"),
    ]:
        d.label(name+"-label",value,x,392,w,parent=parent,size=13)
    d.label("igw-label","IGW",352,824,64,parent="vpc",size=14)
    d.label("ec2-label","EC2",704,784,96,parent="ec2")
    d.label("ebs-label","EBS",928,784,96,parent="ec2")
    d.label("nginx-label","Nginx",524,736,88,parent="nginx")
    d.label("task-label","Task",504,816,80,parent="task",size=14,align="left")
    d.label("gateway-label","Gateway",544,868,144,parent="gateway",align="left")
    d.label("service-label","Service",824,868,192,parent="service",align="left")
    d.label("rds-label","RDS Primary",1152,816,240,parent="rds")
    for number,x,y,parent in [
        ("01",192,296,"terraform"),("02",364,184,"region"),
        ("03",440,528,"vpc"),("04",484,624,"public"),
        ("05",788,716,"ec2"),("06",1012,716,"ec2"),
        ("07",500,320,"management"),("08",592,320,"management"),
        ("09",396,788,"vpc"),("10",192,92,"github"),
        ("11",716,320,"artifacts"),("16",192,808,"browser"),
        ("17",192,512,"dns"),("18",596,716,"nginx"),
        ("19",1308,748,"rds"),("20",1396,320,"secret"),
        ("21",808,320,"artifacts"),("22a",1172,624,"private-a"),
        ("24",696,852,"gateway"),("25",1032,852,"service"),
        ("26",932,320,"platform"),("27",1024,320,"platform"),
        ("28",1148,320,"schedule"),("29",1240,320,"schedule"),
        ("30",1044,816,"task"),
    ]:
        d.marker(number,x,y,parent=parent)
    d.edge("github-terraform","github","terraform",(152,208),(152,264),"M152 208V264")
    d.edge("github-ecr","github","ecr-mark",(256,144),(1008,320),"M256 144H1000Q1008 144 1008 152V320",((1008,144),),kind="optional")
    d.edge("terraform-aws","terraform","aws",(256,336),(304,336),"M256 336H304",kind="control")
    d.edge("browser-dns","browser","dns",(144,776),(144,624),"M144 776V624")
    d.edge("browser-web","browser","igw-mark",(256,848),(352,768),"M256 848H320Q328 848 328 840V776Q328 768 336 768H352",((328,848),(328,768)),kind="web")
    d.edge("web-nginx","igw-mark","nginx",(416,768),(464,752),"M416 768H432Q440 768 440 760V752H464",((440,768),(440,752)),kind="web")
    d.edge("nginx-gateway","nginx","gateway",(600,784),(600,848),"M600 784V848",kind="optional")
    d.edge("gateway-service","gateway","service",(720,880),(752,880),"M720 880H752",kind="optional")
    d.edge("service-rds","service","rds",(1056,880),(1140,880),"M1056 880H1140",kind="optional")
    d.edge("ssm-control","management","ec2",(496,440),(640,680),"M496 440V464Q496 472 504 472H632Q640 472 640 480V680",((496,472),(640,472)),kind="control")
    d.edge("ecs-control","platform","ec2",(944,440),(768,680),"M944 440V488Q944 496 936 496H776Q768 496 768 504V680",((944,496),(768,496)),kind="control")
    d.edge("schedule-ec2","schedule","ec2",(1168,440),(1080,704),"M1168 440V472Q1168 480 1160 480H1112Q1104 480 1104 488V696Q1104 704 1096 704H1080",((1168,480),(1104,480),(1104,704)),kind="control")
    d.edge("schedule-rds","schedule","rds",(1248,440),(1368,680),"M1248 440V488Q1248 496 1256 496H1360Q1368 496 1368 504V680",((1248,496),(1368,496)),kind="control")
    d.edge("ddns-update","ec2","dns",(600,928),(256,552),"M600 928V1048Q600 1056 592 1056H288Q280 1056 280 1048V856a8 8 0 0 1 0 -16V560Q280 552 272 552H256",((600,1056),(280,1056),(280,552)))
    labels = {item["name"] for item in d.items if item["kind"] == "label"}
    for item in d.items:
        if item["kind"] == "icon" and item["name"].removesuffix("-mark") + "-label" not in labels:
            raise ValueError(f"Missing icon label: {item['name']}")
    svg = d.svg()
    prose = "월 5만 원 예산의 구현안이다. 서울 리전에서 ECS on EC2 한 대와 Single-AZ RDS Primary 한 대를 사용한다. Gateway와 Service는 같은 ECS 태스크의 컨테이너 두 개다. Service 내부의 업무 모듈을 별도 서버로 나누지 않는다."
    html = f'''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OpenStudy AWS 아키텍처</title><style>
body{{margin:0;background:#fff;color:{INK};font-family:{SANS};line-height:1.7}}main{{max-width:1600px;margin:20px auto;padding:0 24px;min-width:0}}p{{margin:16px 0;font-size:16px}}a{{color:#405B7D}}.diagram-container{{width:100%;overflow-x:auto}}svg{{display:block;width:100%;min-width:1600px}}@media print{{.diagram-container{{overflow-x:visible}}svg{{min-width:0}}}}
</style></head><body><main><h1>OpenStudy AWS 아키텍처</h1><div class="diagram-container">{svg}</div><p>{prose}</p><p>그림에는 작은 원형 번호와 짧은 영문 이름만 표시한다. 모든 서비스에 아이콘과 이름을 표시한다. DuckDNS와 GitHub는 사용자가 제공한 로고를 사용한다. 설명과 범례는 그림 밖에 둔다.</p><p>30번 Task 안의 24번 Gateway와 25번 Service는 컨테이너 아이콘으로 표시한 향후 앱이다. 18번 Nginx도 별도 웹 컨테이너다. 실제 AMD64 이미지 두 개를 지정하기 전에는 태스크와 ECS 서비스를 생성하지 않는다. 현재는 임시 앱을 배포하지 않는다. 26번 ECS와 27번 ECR은 컨테이너 실행 관리와 이미지 저장에 사용한다.</p><p>19번은 유일한 DB Primary다. multi_az = false이며 대기 DB는 없다. 보조 AZ와 두 번째 서브넷은 그림에서 생략했다. 실제 Terraform의 RDS 서브넷 그룹에는 서로 다른 AZ의 두 프라이빗 서브넷이 필요하다. 22a번은 Primary를 배치하는 서브넷이다. 현재 EC2와 Primary는 ap-northeast-2b에 배치한다.</p><p>10번 GitHub는 소스 저장소와 배포 시작점을 표시한다. GitHub → Terraform은 인프라 코드 경로다. GitHub → ECR의 긴 점선은 향후 GitHub Actions의 AMD64 이미지 빌드·게시 경로다. Actions 연결과 실제 앱 이미지는 아직 구현 전이다.</p><p>28번 Scheduler와 29번 Lambda가 평일 서울 시간 11:00에 시작한다. 매일 18:00에 중지하고 18:30에 다시 확인한다. 시작 후 EC2·RDS 준비와 DNS 갱신 시간이 추가로 필요하다. 중지 시간에도 EBS·RDS 저장 공간은 과금한다.</p><p>05번 EC2는 c7i-flex.large, 06번 EBS는 gp3 30GiB다. Nginx가 HTTPS와 정적 웹을 제공한다. 앱 준비 후 API 요청은 Nginx → Gateway → Service → RDS 순서로 처리한다. 외부에는 80·443만 허용한다.</p><p>07·08번은 SSM과 Parameter Store다. 11·21번은 웹·SQL 배포용 S3다. 20번 Secrets Manager는 DB 관리자 비밀번호를 관리한다. 실제 비밀번호와 토큰은 그림과 Git에 넣지 않는다. 짧은 점선은 관리 작업, 긴 점선은 향후 앱의 요청 경로다.</p><p>2026-10-22에 Nginx·Frontend·Single-AZ RDS·운영 스케줄을 배포했다. 공개 HTTPS, 업무 테이블 58개와 Flyway 이력 1개, TLS DB 연결과 Lambda 시작 요청을 확인했다. 자동 백업과 삭제 시 최종 스냅샷은 사용자 요청으로 비활성화했다. 적용 후 계획은 No changes였다. 이후 오늘 사용 종료 요청으로 EC2와 RDS를 모두 중지했다. 다음 자동 시작 예정은 2026-10-23 서울 시간 11:00이다. Gateway와 Service는 실제 이미지 준비 후 연결한다.</p><p><a href="{STEM}.drawio">draw.io 편집 파일</a> · <a href="{STEM}.svg">SVG</a> · <a href="../architecture.md">최신 아키텍처와 구성 요소 설명</a></p></main></body></html>'''
    (IMAGES / f"{STEM}.html").write_text(html)
    (IMAGES / f"{STEM}.svg").write_text(svg)
    (IMAGES / f"{STEM}.drawio").write_text(d.drawio())
    print("Generated numbered AWS architecture HTML, SVG and editable draw.io source.")


if __name__ == "__main__":
    main()
