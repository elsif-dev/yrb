# frozen_string_literal: true

RSpec.describe Y::XMLFragment do
  it "creates new XMLFragment" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")

    expect(xml_fragment.to_s).to eq("")
  end

  it "inserts new node at index" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment[0] = "firstNode"

    expect(xml_fragment.to_s).to eq("<firstNode></firstNode>")
  end

  it "retrieve node from index" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment[0] = "firstNode"

    expect(xml_fragment[0].to_s).to eq("<firstNode></firstNode>")
  end

  it "retrieves first child from element" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment[0] = "root"

    expect(xml_fragment.first_child.to_s).to eq("<root></root>")
  end

  it "retrieves adjacent element or text (next)" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    a = xml_fragment << "A"
    b = xml_fragment << "B"

    expect(a.next_sibling.tag).to eq(b.tag)
  end

  it "retrieves parent element" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    a = xml_fragment << "A"

    expect(a.parent).to be_a(described_class)
  end

  it "retrieves adjacent element or text (previous)" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    a = xml_fragment << "A"
    b = xml_fragment << "B"

    expect(b.prev_sibling.tag).to eq(a.tag)
  end

  it "pushes child to the end of the child list" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment << "A"
    b = xml_fragment << "B"

    expect(xml_fragment[1].tag).to eq(b.tag)
  end

  it "push functions as an alias to <<" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment.push "A"
    b = xml_fragment.push "B"

    expect(xml_fragment[1].tag).to eq(b.tag)
  end

  it "returns size of child list" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment << "A"
    xml_fragment << "B"

    expect(xml_fragment.size).to eq(2)
  end

  it "returns string representation of element" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("root")
    a = xml_fragment << "A"
    a << "B"

    expect(xml_fragment.to_s).to eq("<A><B></B></A>")
  end

  it "adds child to the front of the child list" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment.unshift "A"
    b = xml_fragment.unshift "B"

    expect(xml_fragment[0].tag).to eq(b.tag)
  end

  it "inserts text at end of children list" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    text = xml_fragment.push_text("Hello")

    expect(text).to be_a(Y::XMLText)
    expect(text.to_s).to eq("Hello")
    expect(xml_fragment.to_s).to eq("Hello")
  end

  it "inserts text at front of children list" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment << "A"
    text = xml_fragment.unshift_text("Front")

    expect(text).to be_a(Y::XMLText)
    expect(xml_fragment.to_s).to start_with("Front")
  end

  it "inserts text at specific index" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment << "A"
    xml_fragment << "B"
    text = xml_fragment.insert_text(1, "Middle")

    expect(text).to be_a(Y::XMLText)
    expect(xml_fragment[1]).to be_a(Y::XMLText)
  end

  it "iterates over children with each" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment << "A"
    xml_fragment << "B"
    xml_fragment << "C"

    children = []
    xml_fragment.each { |child| children << child }

    expect(children.length).to eq(3)
    expect(children.map(&:tag)).to eq(%w[A B C])
  end

  it "supports Enumerable methods like select" do
    doc = Y::Doc.new
    xml_fragment = doc.get_xml_fragment("default")
    xml_fragment << "A"
    xml_fragment << "B"

    result = xml_fragment.select { |child| child.tag == "A" }

    expect(result.length).to eq(1)
  end
end
