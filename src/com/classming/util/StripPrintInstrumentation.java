package com.classming.util;

import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

public class StripPrintInstrumentation {
    public static void main(String[] args) throws IOException {
        if (args.length != 2) {
            System.err.println("Usage: StripPrintInstrumentation <input.class> <output.class>");
            System.exit(1);
        }

        File input = new File(args[0]);
        File output = new File(args[1]);
        strip(input, output);
    }

    public static void strip(File input, File output) throws IOException {
        byte[] classBytes = readAll(input);
        ClassReader reader = new ClassReader(classBytes);
        ClassNode classNode = new ClassNode();
        reader.accept(classNode, 0);

        for (Object methodObject : classNode.methods) {
            MethodNode method = (MethodNode) methodObject;
            removePrintLogCalls(method.instructions);
        }

        ClassWriter writer = new ClassWriter(0);
        classNode.accept(writer);

        File parent = output.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }

        FileOutputStream out = new FileOutputStream(output);
        try {
            out.write(writer.toByteArray());
        } finally {
            out.close();
        }
    }

    private static void removePrintLogCalls(InsnList instructions) {
        for (AbstractInsnNode insn = instructions.getFirst(); insn != null; ) {
            AbstractInsnNode next = insn.getNext();
            if (isPrintLogCall(insn)) {
                AbstractInsnNode previous = insn.getPrevious();
                instructions.remove(insn);
                if (previous instanceof LdcInsnNode && ((LdcInsnNode) previous).cst instanceof String) {
                    instructions.remove(previous);
                }
            }
            insn = next;
        }
    }

    private static boolean isPrintLogCall(AbstractInsnNode insn) {
        if (!(insn instanceof MethodInsnNode)) {
            return false;
        }
        MethodInsnNode methodInsn = (MethodInsnNode) insn;
        return "Print".equals(methodInsn.owner)
                && "logPrint".equals(methodInsn.name)
                && "(Ljava/lang/String;)V".equals(methodInsn.desc);
    }

    private static byte[] readAll(File file) throws IOException {
        long length = file.length();
        if (length > Integer.MAX_VALUE) {
            throw new IOException("Class file too large: " + file);
        }

        byte[] bytes = new byte[(int) length];
        FileInputStream in = new FileInputStream(file);
        try {
            int offset = 0;
            while (offset < bytes.length) {
                int read = in.read(bytes, offset, bytes.length - offset);
                if (read < 0) {
                    break;
                }
                offset += read;
            }
            if (offset != bytes.length) {
                throw new IOException("Could not completely read file: " + file);
            }
            return bytes;
        } finally {
            in.close();
        }
    }
}
